import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var usageData: UsageData?
    var isLoading = false
    var errorMessage: String?
    var isSetupComplete = false

    var settings: AppSettings = .default {
        didSet {
            trySaveSettings()
            if oldValue.refreshInterval != settings.refreshInterval {
                startRefreshLoop()
            }
        }
    }

    private let keychain = KeychainRepository()
    private let settingsRepo = SettingsRepository()
    private let usageService = UsageService()
    let updateChecker = UpdateChecker()
    let autoUpdater = AutoUpdater()
    let notificationService = NotificationService()
    let historyService = UsageHistoryService()

    private var refreshTask: Task<Void, Never>?

    func bootstrap() {
        settings = settingsRepo.load()
        isSetupComplete = keychain.exists()

        if isSetupComplete {
            Task { await refresh() }
            startRefreshLoop()
        }

        Task { await notificationService.requestPermission() }

        Task {
            guard let update = await updateChecker.check() else { return }
            autoUpdater.startUpdate(update)
        }
    }

    func refresh() async {
        guard isSetupComplete else { usageData = nil; return }
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let key = try keychain.retrieve()
            let orgId: String
            if let cached = settings.cachedOrganizationId {
                orgId = cached
            } else {
                orgId = try await usageService.validateKey(try SessionKey(key))
                settings.cachedOrganizationId = orgId
            }
            do {
                usageData = try await usageService.fetchUsage(sessionKey: key, organizationId: orgId)
            } catch AppError.organizationNotFound {
                // Cached org ID may be stale — re-validate and retry once.
                let freshOrgId = try await usageService.validateKey(try SessionKey(key))
                settings.cachedOrganizationId = freshOrgId
                do {
                    usageData = try await usageService.fetchUsage(sessionKey: key, organizationId: freshOrgId)
                } catch AppError.organizationNotFound {
                    // Correct org ID confirmed but still 403 — account lacks usage API access.
                    throw AppError.usageAccessDenied
                }
            }
            if let data = usageData {
                notificationService.check(data, enabled: settings.notificationsEnabled,
                                          threshold: settings.notificationThreshold)
                historyService.record(data)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSessionKey(_ raw: String) async throws {
        let key = try SessionKey(raw)
        let orgId = try await usageService.validateKey(key)
        try keychain.save(key.value)
        settings.cachedOrganizationId = orgId
        isSetupComplete = true
        await refresh()
        startRefreshLoop()
    }

    func clearSessionKey() throws {
        try keychain.delete()
        settings.cachedOrganizationId = nil
        isSetupComplete = false
        usageData = nil
        errorMessage = nil
        refreshTask?.cancel()
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
