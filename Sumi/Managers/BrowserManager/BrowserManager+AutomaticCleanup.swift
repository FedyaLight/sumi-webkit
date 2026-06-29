@MainActor
extension BrowserManager {
    @discardableResult
    func runAutomaticPermissionCleanupIfNeeded(
        for profile: Profile?
    ) async -> SumiPermissionCleanupResult? {
        guard let profile else { return nil }
        let repository = SumiPermissionSettingsRepository(browserManager: self)
        return await repository.runAutomaticCleanupIfNeeded(
            profile: SumiPermissionSettingsProfileContext(profile: profile)
        )
    }

    func scheduleAutomaticBrowsingDataCleanup(
        reason: String,
        force: Bool = false,
        delayNanoseconds: UInt64? = nil
    ) {
        guard let sumiSettings else { return }
        dataServices.automaticBrowsingDataCleanupService.scheduleIfNeeded(
            retentionPeriod: sumiSettings.browsingDataRetentionPeriod,
            historyManager: historyManager,
            profiles: profileManager.profiles,
            currentProfileId: currentProfile?.id,
            force: force,
            reason: reason,
            delayNanoseconds: delayNanoseconds
        )
    }
}
