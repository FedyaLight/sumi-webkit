import Foundation
import SumiDomain

/// Schedules automatic permission cleanup and browsing-data retention cleanup
/// from settings, profile switches, and retention-change notifications.
@MainActor
final class BrowserAutomaticDataCleanupOwner {
    private let permissionRuntimeAction: @MainActor () -> BrowserManagerPermissionRuntime?
    private let dataServicesAction: @MainActor () -> BrowserManagerDataServices?
    private let retentionPeriodAction: @MainActor () -> SumiBrowsingDataRetentionPeriod?
    private let historyManagerAction: @MainActor () -> HistoryManager?
    private let profilesAction: @MainActor () -> [Profile]
    private let currentProfileIdAction: @MainActor () -> UUID?

    init(
        permissionRuntime: @escaping @MainActor () -> BrowserManagerPermissionRuntime?,
        dataServices: @escaping @MainActor () -> BrowserManagerDataServices?,
        retentionPeriod: @escaping @MainActor () -> SumiBrowsingDataRetentionPeriod?,
        historyManager: @escaping @MainActor () -> HistoryManager?,
        profiles: @escaping @MainActor () -> [Profile],
        currentProfileId: @escaping @MainActor () -> UUID?
    ) {
        self.permissionRuntimeAction = permissionRuntime
        self.dataServicesAction = dataServices
        self.retentionPeriodAction = retentionPeriod
        self.historyManagerAction = historyManager
        self.profilesAction = profiles
        self.currentProfileIdAction = currentProfileId
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
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

    @discardableResult
    func runAutomaticPermissionCleanupIfNeeded(
        for profile: Profile?
    ) async -> SumiPermissionCleanupResult? {
        guard let profile,
              let permissionRuntime = permissionRuntimeAction(),
              let dataServices = dataServicesAction()
        else { return nil }
        let repository = SumiPermissionSettingsRepository(
            permissionRuntime: permissionRuntime,
            dataServices: dataServices,
            autoplayStore: permissionRuntime.autoplayStore
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
        guard let retentionPeriod = retentionPeriodAction(),
              let historyManager = historyManagerAction(),
              let dataServices = dataServicesAction()
        else { return }
        let request = SumiBrowsingDataCleanupScheduleRequest(
            retentionPeriod: retentionPeriod,
            historyManager: historyManager,
            profiles: profilesAction(),
            currentProfileId: currentProfileIdAction(),
            force: force,
            reason: reason,
            delayNanoseconds: delayNanoseconds
        )
        dataServices.automaticBrowsingDataCleanupService.scheduleIfNeeded(request)
    }
}
