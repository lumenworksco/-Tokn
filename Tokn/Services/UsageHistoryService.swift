import Foundation

struct UsagePoint: Codable, Sendable {
    let date: Date
    let sessionPct: Double
    let weeklyPct: Double
}

final class UsageHistoryService: @unchecked Sendable {
    private static let legacyKey = "com.tokn.usageHistory"
    private let maxPts = 48   // ~48 h at 1-min refresh, or ~8 h at 10-min

    private func key(for accountId: UUID) -> String { "\(Self.legacyKey).\(accountId.uuidString)" }

    func record(_ data: UsageData, for accountId: UUID) {
        var pts = load(for: accountId)
        pts.append(UsagePoint(
            date: data.lastUpdated,
            sessionPct: data.sessionUsage.utilization,
            weeklyPct:  data.weeklyUsage.utilization
        ))
        if pts.count > maxPts { pts = Array(pts.suffix(maxPts)) }
        if let encoded = try? JSONEncoder().encode(pts) {
            UserDefaults.standard.set(encoded, forKey: key(for: accountId))
        }
    }

    func load(for accountId: UUID) -> [UsagePoint] {
        guard let data = UserDefaults.standard.data(forKey: key(for: accountId)),
              let pts  = try? JSONDecoder().decode([UsagePoint].self, from: data) else {
            return []
        }
        return pts
    }

    func delete(for accountId: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: accountId))
    }

    /// Moves single-account history onto the account created during migration.
    func migrateLegacy(to accountId: UUID) {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.legacyKey) else { return }
        defaults.set(data, forKey: key(for: accountId))
        defaults.removeObject(forKey: Self.legacyKey)
    }
}
