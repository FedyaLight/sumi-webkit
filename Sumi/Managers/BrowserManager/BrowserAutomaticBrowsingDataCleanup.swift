import Foundation

@MainActor
final class BrowserAutomaticBrowsingDataCleanup {
    private let settings: BrowserSettingsState
    private let history: HistoryManager
    private let dataServices: BrowserManagerDataServices
    private let profiles: ProfileManager
    private let currentProfile: BrowserCurrentProfileAuthority

    init(
        settings: BrowserSettingsState,
        history: HistoryManager,
        dataServices: BrowserManagerDataServices,
        profiles: ProfileManager,
        currentProfile: BrowserCurrentProfileAuthority
    ) {
        self.settings = settings
        self.history = history
        self.dataServices = dataServices
        self.profiles = profiles
        self.currentProfile = currentProfile
    }

    func schedule(
        reason: String,
        force: Bool = false,
        delayNanoseconds: UInt64? = nil
    ) {
        guard let retentionPeriod = settings.settings?
            .browsingDataRetentionPeriod else { return }
        dataServices.automaticBrowsingDataCleanupService.scheduleIfNeeded(
            SumiBrowsingDataCleanupScheduleRequest(
                retentionPeriod: retentionPeriod,
                historyManager: history,
                profileIDs: profiles.profiles
                    .filter { !$0.isEphemeral }
                    .map(\.id),
                currentProfileId: currentProfile.currentProfile?.id,
                force: force,
                reason: reason,
                delayNanoseconds: delayNanoseconds
            )
        )
    }
}
