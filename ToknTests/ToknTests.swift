import XCTest
@testable import Tokn

final class UsageLimitTests: XCTestCase {
    private func limit(_ u: Double, in seconds: TimeInterval = 3600) -> UsageLimit {
        UsageLimit(utilization: u, resetAt: Date().addingTimeInterval(seconds))
    }

    func testStatusBoundaries() {
        XCTAssertEqual(limit(0).status, .safe)
        XCTAssertEqual(limit(49.9).status, .safe)
        XCTAssertEqual(limit(50).status, .warning)
        XCTAssertEqual(limit(79.9).status, .warning)
        XCTAssertEqual(limit(80).status, .critical)
        XCTAssertEqual(limit(100).status, .critical)
    }

    func testIsExceeded() {
        XCTAssertFalse(limit(99.9).isExceeded)
        XCTAssertTrue(limit(100).isExceeded)
        XCTAssertTrue(limit(120).isExceeded)
    }

    func testResetDescriptions() {
        XCTAssertEqual(limit(10, in: -5).resetDescription, "Resets now")
        XCTAssertEqual(limit(10, in: 30 * 60).shortResetDescription, "30m")
        XCTAssertEqual(limit(10, in: 2 * 3600 - 10).shortResetDescription, "2h")
        XCTAssertEqual(limit(10, in: 3 * 86400 - 10).shortResetDescription, "3d")
    }
}

final class SessionKeyTests: XCTestCase {
    func testBareToken() throws {
        let raw = "sk-ant-sid01-abcdefghijklmnopqrstuvwxyz"
        XCTAssertEqual(try SessionKey("  \(raw)\n").value, raw)
    }

    func testCookieString() throws {
        let raw = "sk-ant-sid01-abcdefghijklmnopqrstuvwxyz"
        XCTAssertEqual(try SessionKey("foo=bar; sessionKey=\(raw); other=1").value, raw)
    }

    func testRejectsEmptyAndShort() {
        XCTAssertThrowsError(try SessionKey("   "))
        XCTAssertThrowsError(try SessionKey("short"))
        XCTAssertThrowsError(try SessionKey("foo=bar"))
    }
}

final class UsageAPIResponseTests: XCTestCase {
    func testDecodesAndMaps() throws {
        let json = """
        {"five_hour":{"utilization":42.5,"resets_at":"2026-10-08T12:00:00.000Z"},
         "seven_day":{"utilization":100,"resets_at":null}}
        """.data(using: .utf8)!
        let data = try JSONDecoder().decode(UsageAPIResponse.self, from: json).toUsageData()
        XCTAssertEqual(data.sessionUsage.utilization, 42.5)
        XCTAssertTrue(data.weeklyUsage.isExceeded)
        // Missing resets_at falls back to roughly a week from now.
        XCTAssertGreaterThan(data.weeklyUsage.resetAt.timeIntervalSinceNow, 6 * 86400)
    }
}

final class AppSettingsTests: XCTestCase {
    func testMissingFieldsGetDefaults() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(s, AppSettings.default)
        XCTAssertFalse(s.autoInstallUpdates)
    }

    func testRefreshIntervalClamped() {
        var s = AppSettings.default
        s.setRefreshInterval(5);    XCTAssertEqual(s.refreshInterval, 60)
        s.setRefreshInterval(9999); XCTAssertEqual(s.refreshInterval, 600)
    }
}

final class UpdateCheckerTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.49", than: "1.0.48"))
        XCTAssertTrue(UpdateChecker.isNewer("1.1", than: "1.0.48"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.10", than: "1.0.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.48", than: "1.0.48"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.47", than: "1.0.48"))
    }

    func testParsePicksDMGAndDigest() throws {
        let json = """
        {"tag_name":"v1.0.49","assets":[
          {"name":"notes.txt","browser_download_url":"https://github.com/x/notes.txt"},
          {"name":"Tokn-1.0.49.dmg","browser_download_url":"https://github.com/x/Tokn.dmg","digest":"sha256:abc123"}]}
        """.data(using: .utf8)!
        let u = try XCTUnwrap(UpdateChecker.parse(json, current: "1.0.48"))
        XCTAssertEqual(u.version, "1.0.49")
        XCTAssertEqual(u.downloadURL?.absoluteString, "https://github.com/x/Tokn.dmg")
        XCTAssertEqual(u.sha256, "abc123")
    }

    func testParseWithoutDigestHasNoChecksum() throws {
        let json = """
        {"tag_name":"v2.0","assets":[{"name":"a.dmg","browser_download_url":"https://github.com/a.dmg"}]}
        """.data(using: .utf8)!
        XCTAssertNil(try XCTUnwrap(UpdateChecker.parse(json, current: "1.0")).sha256)
    }

    func testParseIgnoresOlderRelease() {
        let json = #"{"tag_name":"v1.0.1","assets":[]}"#.data(using: .utf8)!
        XCTAssertNil(UpdateChecker.parse(json, current: "1.0.48"))
    }

    func testTrustedHosts() {
        XCTAssertTrue(UpdateInfo.isTrusted(URL(string: "https://github.com/a/b.dmg")!))
        XCTAssertTrue(UpdateInfo.isTrusted(URL(string: "https://objects.githubusercontent.com/x")!))
        XCTAssertFalse(UpdateInfo.isTrusted(URL(string: "http://github.com/a.dmg")!))
        XCTAssertFalse(UpdateInfo.isTrusted(URL(string: "https://evil.com/github.com")!))
        XCTAssertFalse(UpdateInfo.isTrusted(URL(string: "https://githubusercontent.com.evil.com/a")!))
    }
}

final class InstallerTests: XCTestCase {
    func testSHA256() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        XCTAssertEqual(try Installer.sha256Hex(of: f),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testChecksumMismatchRejected() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).dmg")
        try Data("not a dmg".utf8).write(to: f)
        let result = Installer.install(dmg: f, expectedSHA256: "deadbeef",
                                       expectedBundleID: "com.tokn.app",
                                       replacing: URL(fileURLWithPath: "/nonexistent/Tokn.app"))
        guard case .failure(let e) = result else { return XCTFail("should reject") }
        XCTAssertTrue(e.message.contains("Checksum"))
    }
}
