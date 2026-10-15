import Foundation
import AppKit
import CryptoKit

@Observable
@MainActor
final class AutoUpdater {
    enum Phase: Equatable {
        case idle
        case downloading(Double)
        case installing
        case failed(String)
    }

    var phase: Phase = .idle

    func startUpdate(_ update: UpdateInfo) {
        guard case .idle = phase else { return }
        guard let url = update.downloadURL, UpdateInfo.isTrusted(url) else {
            phase = .failed("No valid download found"); return
        }
        // Never install code we can't verify against the checksum GitHub published for the asset.
        guard let sha256 = update.sha256 else {
            phase = .failed("Update can't be verified — download it from GitHub"); return
        }
        phase = .downloading(0)
        Task { await run(url: url, expectedSHA256: sha256) }
    }

    func reset() { phase = .idle }

    private func run(url: URL, expectedSHA256: String) async {
        let downloader = Downloader { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.phase else { return }
                self.phase = .downloading(fraction)
            }
        }

        let dmg: URL
        do {
            dmg = try await downloader.download(url)
        } catch {
            phase = .failed("Download failed: \(error.localizedDescription)")
            return
        }

        phase = .installing
        let target = Bundle.main.bundleURL
        let expectedID = Bundle.main.bundleIdentifier
        let result = await Task.detached(priority: .userInitiated) {
            Installer.install(dmg: dmg, expectedSHA256: expectedSHA256,
                              expectedBundleID: expectedID, replacing: target)
        }.value

        switch result {
        case .success:
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            relaunch.arguments = ["-n", target.path]
            try? relaunch.run()
            NSApplication.shared.terminate(nil)
        case .failure(let error):
            phase = .failed(error.message)
        }
    }
}

// MARK: - Download

// Downloads to disk in large chunks (URLSession's download task) and reports progress.
private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    init(onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

    func download(_ url: URL) async throws -> URL {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let c = continuation else { return }
        continuation = nil
        c.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData _: Int64, totalBytesWritten written: Int64,
                    totalBytesExpectedToWrite total: Int64) {
        if total > 0 { onProgress(min(1, Double(written) / Double(total))) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            finish(.failure(URLError(.badServerResponse))); return
        }
        // The system deletes `location` when this method returns, so move it now.
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tokn-update-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            finish(.success(kept))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}

// MARK: - Install

struct InstallError: Error { let message: String }

enum Installer {
    static func install(dmg: URL, expectedSHA256: String, expectedBundleID: String?,
                        replacing target: URL) -> Result<Void, InstallError> {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: dmg) }

        guard let actual = try? sha256Hex(of: dmg), actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            return .failure(InstallError(message: "Checksum mismatch — update rejected"))
        }

        // Private, unpredictable working directory (0700) instead of a fixed /tmp path.
        let work = fm.temporaryDirectory.appendingPathComponent("tokn-update-\(UUID().uuidString)")
        let mount = work.appendingPathComponent("mnt")
        do {
            try fm.createDirectory(at: mount, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } catch {
            return .failure(InstallError(message: "Could not prepare update"))
        }
        defer { try? fm.removeItem(at: work) }

        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-readonly", "-nobrowse",
                                       "-noautoopen", "-mountpoint", mount.path]) == 0 else {
            return .failure(InstallError(message: "Could not mount update"))
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

        let src = mount.appendingPathComponent("Tokn.app")
        guard Bundle(url: src)?.bundleIdentifier == expectedBundleID, expectedBundleID != nil else {
            return .failure(InstallError(message: "Update isn't Tokn — rejected"))
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", src.path]) == 0 else {
            return .failure(InstallError(message: "Update signature invalid — rejected"))
        }

        // Stage next to the destination, then swap atomically. If anything fails the
        // existing app is left untouched.
        let staged = target.deletingLastPathComponent()
            .appendingPathComponent(".Tokn-update-\(UUID().uuidString).app")
        do {
            try fm.copyItem(at: src, to: staged)
            _ = run("/usr/bin/xattr", ["-cr", staged.path])
            _ = try fm.replaceItemAt(target, withItemAt: staged)
        } catch {
            try? fm.removeItem(at: staged)
            return .failure(InstallError(message: "Could not replace app — try dragging manually"))
        }
        return .success(())
    }

    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private static func run(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
