import UserNotifications
import Foundation

@Observable
@MainActor
final class NotificationService {

    // Per-account, per-type threshold tracking: key = "<account id>.Session" etc.,
    // value = highest notified threshold
    private var notifiedAt: [String: Int] = [:]

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// `accountLabel` is shown in the alert only when it's needed to tell accounts apart.
    func check(_ data: UsageData, account: Account, accountLabel: String?, enabled: Bool, threshold: Int) {
        guard enabled else { return }
        checkLimit(data.sessionUsage, name: "Session", account: account, label: accountLabel, threshold: threshold)
        checkLimit(data.weeklyUsage,  name: "Weekly",  account: account, label: accountLabel, threshold: threshold)
    }

    func forget(_ accountId: UUID) {
        notifiedAt = notifiedAt.filter { !$0.key.hasPrefix(accountId.uuidString) }
    }

    private func checkLimit(_ limit: UsageLimit, name: String, account: Account, label: String?, threshold: Int) {
        let pct = Int(limit.utilization)
        let thresholds = [threshold, 100]
        let trackKey = "\(account.id.uuidString).\(name)"

        for t in thresholds where pct >= t {
            if (notifiedAt[trackKey] ?? 0) < t {
                notifiedAt[trackKey] = t
                send(name: name, accountId: account.id, label: label, threshold: t, pct: pct)
            }
        }

        // Reset tracking when usage falls 5pp below the first threshold
        if pct < max(threshold - 5, 0) { notifiedAt[trackKey] = 0 }
    }

    static func identifier(accountId: UUID, name: String, threshold: Int) -> String {
        "tokn.\(accountId.uuidString).\(name.lowercased()).\(threshold)"
    }

    private func send(name: String, accountId: UUID, label: String?, threshold: Int, pct: Int) {
        let content = UNMutableNotificationContent()
        let prefix = label.map { "\($0): " } ?? ""
        if threshold >= 100 {
            content.title = "Claude limit reached"
            content.body  = "\(prefix)\(name) usage is at \(pct)% — you've hit the limit"
        } else {
            content.title = "Claude usage at \(threshold)%"
            content.body  = "\(prefix)\(name) is \(pct)% used"
        }
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: Self.identifier(accountId: accountId, name: name, threshold: threshold),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
