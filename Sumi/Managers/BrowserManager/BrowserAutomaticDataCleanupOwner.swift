import Foundation

/// Schedules automatic permission cleanup and browsing-data retention cleanup
/// from settings, profile switches, and retention-change notifications.
@MainActor
final class BrowserAutomaticDataCleanupOwner {
    struct Dependencies {
        let permissionRuntime: @MainActor () -> BrowserManagerPermissionRuntime?
        let dataServices: @MainActor () -> BrowserManagerDataServices?
        let retentionPeriod: @MainActor () -> SumiBrowsingDataRetentionPeriod?
        let historyManager: @MainActor () -> HistoryManager?
        let profiles: @MainActor () -> [Profile]
        let currentProfileId: @MainActor () -> UUID?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func runAutomaticPermissionCleanupIfNeeded(
        for profile: Profile?
    ) async -> SumiPermissionCleanupResult? {
        guard let profile,
              let permissionRuntime = dependencies.permissionRuntime(),
              let dataServices = dependencies.dataServices()
        else { return nil }
        let repository = SumiPermissionSettingsRepository(
            permissionRuntime: permissionRuntime,
            dataServices: dataServices
        )
        return await repository.runAutomaticCleanupIfNeeded(
            profile: SumiPermissionSettingsProfileContext(profile: profile)
        )
    }

    func scheduleAutomaticBrowsingDataCleanup(
        reason: String,
        force: Bool = false,
        delayNanoseconds: UInt64? = nil
    ) {
        guard let retentionPeriod = dependencies.retentionPeriod(),
              let historyManager = dependencies.historyManager(),
              let dataServices = dependencies.dataServices()
        else { return }
        let request = SumiBrowsingDataCleanupScheduleRequest(
            retentionPeriod: retentionPeriod,
            historyManager: historyManager,
            profiles: dependencies.profiles(),
            currentProfileId: dependencies.currentProfileId(),
            force: force,
            reason: reason,
            delayNanoseconds: delayNanoseconds
        )
        dataServices.automaticBrowsingDataCleanupService.scheduleIfNeeded(request)
    }
}

extension BrowserAutomaticDataCleanupOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            permissionRuntime: { [weak browserManager] in
                browserManager?.permissionRuntime
            },
            dataServices: { [weak browserManager] in
                browserManager?.dataServices
            },
            retentionPeriod: { [weak browserManager] in
                browserManager?.sumiSettings?.browsingDataRetentionPeriod
            },
            historyManager: { [weak browserManager] in
                browserManager?.historyManager
            },
            profiles: { [weak browserManager] in
                browserManager?.profileManager.profiles ?? []
            },
            currentProfileId: { [weak browserManager] in
                browserManager?.currentProfile?.id
            }
        )
    }
}
