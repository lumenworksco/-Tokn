import Foundation

struct UpdateInfo: Equatable, Sendable {
    let version: String
    let downloadURL: URL?
    let sha256: String?   // from the asset digest GitHub publishes ("sha256:<hex>")

    // Only ever download updates over HTTPS from GitHub's release hosts.
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }
}

@Observable
@MainActor
final class UpdateChecker {
    var available: UpdateInfo?
    var availableVersion: String? { available?.version }

    private let current: String
    private let apiURL = URL(string: "https://api.github.com/repos/lumenworksco/-Tokn/releases/latest")!

    init() {
        current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // Returns the update if a newer release exists, nil otherwise.
    func check() async -> UpdateInfo? {
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let update = Self.parse(data, current: current) else { return nil }
        available = update
        return update
    }

    nonisolated static func parse(_ data: Data, current: String) -> UpdateInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag  = json["tag_name"] as? String else { return nil }
        let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(remote, than: current) else { return nil }

        // Pick the .dmg asset by name rather than trusting asset order.
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
        let url = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))
        var sha: String?
        if let digest = dmg?["digest"] as? String, digest.hasPrefix("sha256:") {
            sha = String(digest.dropFirst("sha256:".count))
        }
        return UpdateInfo(version: remote, downloadURL: url, sha256: sha)
    }

    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator:  ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}
