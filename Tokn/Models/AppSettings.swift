import Foundation

enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    case dotAndPercent = "dot + %"
    case percentOnly   = "% only"
    case dotOnly       = "dot only"
}

/// One Claude login. The session key itself lives in the Keychain under `keychainAccount`.
struct Account: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var label: String
    var organizationId: String?

    init(id: UUID = UUID(), label: String, organizationId: String? = nil) {
        self.id = id
        self.label = label
        self.organizationId = organizationId
    }

    var keychainAccount: String { "session-key.\(id.uuidString)" }
}

struct AppSettings: Codable, Equatable, Sendable {
    var refreshInterval: TimeInterval
    var cachedOrganizationId: String?   // legacy single-account field, only read for migration
    var accounts: [Account]
    var selectedAccountId: UUID?        // account shown in the menu bar and popover
    var notificationsEnabled: Bool
    var notificationThreshold: Int      // first alert threshold (50–90%); 100% always fires
    var launchAtLogin: Bool
    var menuBarStyle: MenuBarStyle
    var autoInstallUpdates: Bool        // off by default: updates need an explicit click

    // CodingKeys kept in the struct body so the synthesized encode(to:) picks them up.
    private enum CodingKeys: String, CodingKey {
        case refreshInterval, cachedOrganizationId, notificationsEnabled,
             notificationThreshold, launchAtLogin, menuBarStyle, autoInstallUpdates,
             accounts, selectedAccountId
    }

    static let `default` = AppSettings(
        refreshInterval: 60,
        cachedOrganizationId: nil,
        accounts: [],
        selectedAccountId: nil,
        notificationsEnabled: true,
        notificationThreshold: 80,
        launchAtLogin: false,
        menuBarStyle: .dotAndPercent,
        autoInstallUpdates: false
    )

    var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountId } ?? accounts.first
    }

    mutating func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = max(60, min(600, interval))
    }
}

// Custom decoder in an extension so the memberwise initializer is preserved.
// decodeIfPresent + defaults means adding new fields never silently resets existing user settings.
extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        refreshInterval       = try c.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval)       ?? 60
        cachedOrganizationId  = try c.decodeIfPresent(String.self,       forKey: .cachedOrganizationId)
        accounts              = try c.decodeIfPresent([Account].self,    forKey: .accounts)              ?? []
        selectedAccountId     = try c.decodeIfPresent(UUID.self,         forKey: .selectedAccountId)
        notificationsEnabled  = try c.decodeIfPresent(Bool.self,         forKey: .notificationsEnabled)  ?? true
        notificationThreshold = try c.decodeIfPresent(Int.self,          forKey: .notificationThreshold) ?? 80
        launchAtLogin         = try c.decodeIfPresent(Bool.self,         forKey: .launchAtLogin)         ?? false
        menuBarStyle          = try c.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle)          ?? .dotAndPercent
        autoInstallUpdates    = try c.decodeIfPresent(Bool.self,         forKey: .autoInstallUpdates)    ?? false
    }
}
