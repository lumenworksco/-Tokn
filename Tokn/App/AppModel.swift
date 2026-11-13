import Foundation
import Observation

enum AccountError: LocalizedError {
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .duplicate(let label): return "That session key is already added as \"\(label)\""
        }
    }
}

/// Which flow the setup screen is showing on top of the usage view.
enum SetupMode: Equatable {
    case add
    case replaceKey(UUID)
}

@MainActor
@Observable
final class AppModel {
    var accountUsage: [UUID: UsageData] = [:]
    var accountErrors: [UUID: String] = [:]
    var loadingAccounts: Set<UUID> = []
    var isRefreshing = false
    var setupMode: SetupMode?
    var isCheckingForUpdates = false
    var updateCheckMessage: String?

    var settings: AppSettings = .default {
        didSet {
            trySaveSettings()
            if oldValue.refreshInterval != settings.refreshInterval {
                startRefreshLoop()
            }
        }
    }

    var accounts: [Account] { settings.accounts }
    var selectedAccount: Account? { settings.selectedAccount }
    var isSetupComplete: Bool { !settings.accounts.isEmpty }

    // Selected-account views of the per-account state, so single-account views stay simple.
    var usageData: UsageData? { selectedAccount.flatMap { accountUsage[$0.id] } }
    var errorMessage: String? { selectedAccount.flatMap { accountErrors[$0.id] } }
    var isLoading: Bool { selectedAccount.map { loadingAccounts.contains($0.id) } ?? false }

    private let settingsRepo = SettingsRepository()
    private let usageService = UsageService()
    let updateChecker = UpdateChecker()
    let autoUpdater = AutoUpdater()
    let notificationService = NotificationService()
    let historyService = UsageHistoryService()

    private var refreshTask: Task<Void, Never>?

    func bootstrap() {
        settings = settingsRepo.load()
        migrateLegacyAccount()

        if isSetupComplete {
            Task { await refresh() }
            startRefreshLoop()
        }

        Task { await notificationService.requestPermission() }

        Task { await checkForUpdates() }
    }

    /// Moves a pre-multi-account session key, org ID and history onto a first account.
    private func migrateLegacyAccount() {
        guard settings.accounts.isEmpty else { return }
        let legacy = KeychainRepository(account: KeychainRepository.legacyAccount)
        guard let key = try? legacy.retrieve() else { return }
        let account = Account(label: "Account 1", organizationId: settings.cachedOrganizationId)
        // Only drop the legacy slot once the key is safely in its new one.
        guard (try? keychain(for: account).save(key)) != nil else { return }
        historyService.migrateLegacy(to: account.id)
        var migrated = settings
        migrated.accounts = [account]
        migrated.selectedAccountId = account.id
        migrated.cachedOrganizationId = nil
        settings = migrated
        try? legacy.delete()
    }

    /// Looks for a newer release. Installs it right away only if the user opted in;
    /// otherwise the update banner offers an explicit button.
    func checkForUpdates(manual: Bool = false) async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        updateCheckMessage = nil
        guard let update = await updateChecker.check() else {
            if manual { updateCheckMessage = "you're up to date" }
            return
        }
        if manual { updateCheckMessage = "v\(update.version) available" }
        if settings.autoInstallUpdates { autoUpdater.startUpdate(update) }
    }

    /// Refreshes every account one after another (not in parallel, to stay clear of rate limits).
    func refresh() async {
        guard isSetupComplete, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for id in settings.accounts.map(\.id) {
            await refreshAccount(id)
        }
    }

    func refreshAccount(_ id: UUID) async {
        guard let account = account(id), !loadingAccounts.contains(id) else { return }
        loadingAccounts.insert(id)
        defer { loadingAccounts.remove(id) }

        do {
            let key = try keychain(for: account).retrieve()
            let orgId: String
            if let cached = account.organizationId {
                orgId = cached
            } else {
                orgId = try await usageService.validateKey(try SessionKey(key)).uuid
                updateAccount(id) { $0.organizationId = orgId }
            }
            let data: UsageData
            do {
                data = try await usageService.fetchUsage(sessionKey: key, organizationId: orgId)
            } catch AppError.organizationNotFound {
                // Cached org ID may be stale — re-validate and retry once.
                let freshOrgId = try await usageService.validateKey(try SessionKey(key)).uuid
                updateAccount(id) { $0.organizationId = freshOrgId }
                do {
                    data = try await usageService.fetchUsage(sessionKey: key, organizationId: freshOrgId)
                } catch AppError.organizationNotFound {
                    // Correct org ID confirmed but still 403 — account lacks usage API access.
                    throw AppError.usageAccessDenied
                }
            }
            // The account may have been removed while the request was in flight.
            guard let current = self.account(id) else { return }
            accountUsage[id] = data
            accountErrors[id] = nil
            notificationService.check(data, account: current,
                                      accountLabel: settings.accounts.count > 1 ? current.label : nil,
                                      enabled: settings.notificationsEnabled,
                                      threshold: settings.notificationThreshold)
            historyService.record(data, for: id)
        } catch {
            guard self.account(id) != nil else { return }
            accountErrors[id] = error.localizedDescription
        }
    }

    /// Adds a new account, or swaps the key of an existing one when `replacing` is set.
    func saveSessionKey(_ raw: String, label: String = "", replacing replaceId: UUID? = nil) async throws {
        let key = try SessionKey(raw)
        if let existing = settings.accounts.first(where: {
            $0.id != replaceId && (try? keychain(for: $0).retrieve()) == key.value
        }) {
            throw AccountError.duplicate(existing.label)
        }
        let org = try await usageService.validateKey(key)

        if let replaceId {
            guard let account = account(replaceId) else { return }
            try keychain(for: account).save(key.value)
            updateAccount(replaceId) { $0.organizationId = org.uuid }
            accountErrors[replaceId] = nil
            setupMode = nil
            await refreshAccount(replaceId)
            return
        }

        var trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        // Labels are stored in plain settings — never let a key pasted into the wrong field land there.
        if trimmed.hasPrefix("sk-ant") || trimmed.contains(key.value) { trimmed = "" }
        let account = Account(
            label: trimmed.isEmpty
                ? Self.defaultLabel(organizationName: org.name, index: settings.accounts.count + 1)
                : trimmed,
            organizationId: org.uuid
        )
        try keychain(for: account).save(key.value)
        let wasEmpty = settings.accounts.isEmpty
        var updated = settings
        updated.accounts.append(account)
        updated.selectedAccountId = account.id
        settings = updated
        setupMode = nil
        await refreshAccount(account.id)
        if wasEmpty { startRefreshLoop() }
    }

    func removeAccount(_ id: UUID) throws {
        guard let account = account(id) else { return }
        try keychain(for: account).delete()
        historyService.delete(for: id)
        notificationService.forget(id)
        accountUsage[id] = nil
        accountErrors[id] = nil
        var updated = settings
        updated.accounts.removeAll { $0.id == id }
        if updated.selectedAccountId == id { updated.selectedAccountId = updated.accounts.first?.id }
        settings = updated
        if settings.accounts.isEmpty { refreshTask?.cancel() }
    }

    func selectAccount(_ id: UUID) {
        guard account(id) != nil else { return }
        settings.selectedAccountId = id
    }

    func renameAccount(_ id: UUID, to label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateAccount(id) { $0.label = trimmed }
    }

    /// Personal orgs are named "<email>'s Organization"; the email alone makes a better label.
    nonisolated static func defaultLabel(organizationName: String?, index: Int) -> String {
        let suffix = "'s Organization"
        guard var name = organizationName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return "Account \(index)" }
        if name.hasSuffix(suffix) { name.removeLast(suffix.count) }
        return name.isEmpty ? "Account \(index)" : name
    }

    private func account(_ id: UUID) -> Account? {
        settings.accounts.first { $0.id == id }
    }

    // Looks the account up by id at call time — never hold an index across an await.
    private func updateAccount(_ id: UUID, _ change: (inout Account) -> Void) {
        guard let i = settings.accounts.firstIndex(where: { $0.id == id }) else { return }
        change(&settings.accounts[i])
    }

    private func keychain(for account: Account) -> KeychainRepository {
        KeychainRepository(account: account.keychainAccount)
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        let interval = settings.refreshInterval
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                await self?.refresh()
            }
        }
    }

    private func trySaveSettings() {
        try? settingsRepo.save(settings)
    }
}
