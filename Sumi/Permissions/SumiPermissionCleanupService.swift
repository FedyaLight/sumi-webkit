import Foundation

@MainActor
final class SumiPermissionCleanupService {
    private enum Constants {
        static let lastRunPrefix = "permissions.cleanup.last-run.v1"
        static let lastRemovedPrefix = "permissions.cleanup.last-removed-count.v1"
        static let throttleInterval: TimeInterval = 24 * 60 * 60
    }

    private let store: any SumiPermissionStore
    private let recentActivityStore: SumiPermissionRecentActivityStore
    private let antiAbuseStore: (any SumiPermissionAntiAbuseStoring)?
    private let userDefaults: UserDefaults
    private let now: () -> Date

    init(
        store: any SumiPermissionStore,
        recentActivityStore: SumiPermissionRecentActivityStore,
        antiAbuseStore: (any SumiPermissionAntiAbuseStoring)? = nil,
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.recentActivityStore = recentActivityStore
        self.antiAbuseStore = antiAbuseStore
        self.userDefaults = userDefaults
        self.now = now
    }

    func settings(
        isAutomaticCleanupEnabled: Bool,
        profilePartitionId: String
    ) -> SumiPermissionCleanupSettings {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return SumiPermissionCleanupSettings(
            isAutomaticCleanupEnabled: isAutomaticCleanupEnabled,
            staleThreshold: SumiPermissionCleanupSettings.defaultThreshold,
            lastRunAt: userDefaults.object(forKey: lastRunKey(profileId)) as? Date,
            lastRemovedCount: userDefaults.object(forKey: lastRemovedKey(profileId)) as? Int
        )
    }

    func lastRunAt(profilePartitionId: String) -> Date? {
        userDefaults.object(
            forKey: lastRunKey(SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId))
        ) as? Date
    }

    @discardableResult
    func runIfNeeded(
        profile: SumiPermissionSettingsProfileContext,
        settings: SumiPermissionCleanupSettings
    ) async -> SumiPermissionCleanupResult {
        let currentDate = now()
        guard settings.isAutomaticCleanupEnabled, !profile.isEphemeralProfile else {
            return .disabled(profilePartitionId: profile.profilePartitionId, now: currentDate)
        }
        if let lastRun = lastRunAt(profilePartitionId: profile.profilePartitionId),
           currentDate.timeIntervalSince(lastRun) < Constants.throttleInterval
        {
            return .throttled(profilePartitionId: profile.profilePartitionId, now: currentDate)
        }
        return await run(profile: profile, settings: settings, force: true)
    }

    @discardableResult
    func run(
        profile: SumiPermissionSettingsProfileContext,
        settings: SumiPermissionCleanupSettings,
        force: Bool = false
    ) async -> SumiPermissionCleanupResult {
        let startedAt = now()
        guard settings.isAutomaticCleanupEnabled, !profile.isEphemeralProfile else {
            return .disabled(profilePartitionId: profile.profilePartitionId, now: startedAt)
        }
        if !force,
           let lastRun = lastRunAt(profilePartitionId: profile.profilePartitionId),
           startedAt.timeIntervalSince(lastRun) < Constants.throttleInterval
        {
            return .throttled(profilePartitionId: profile.profilePartitionId, now: startedAt)
        }

        do {
            let records = try await store.listDecisions(profilePartitionId: profile.profilePartitionId)
            var removedEvents: [SumiPermissionAutoRevokedEvent] = []

            for record in records {
                guard isCleanupEligible(record, now: startedAt, threshold: settings.staleThreshold) else {
                    continue
                }

                try await store.resetDecision(for: record.key)
                let event = SumiPermissionAutoRevokedEvent(
                    displayDomain: record.displayDomain,
                    key: record.key,
                    revokedAt: startedAt
                )
                removedEvents.append(event)
                recentActivityStore.recordAutoRevoked(event)
                await antiAbuseStore?.record(
                    SumiPermissionAntiAbuseEvent(
                        type: .autoRevokedByCleanup,
                        key: record.key,
                        createdAt: startedAt,
                        reason: "unused-site-permission-cleanup"
                    )
                )
            }

            let finishedAt = now()
            userDefaults.set(finishedAt, forKey: lastRunKey(profile.profilePartitionId))
            userDefaults.set(removedEvents.count, forKey: lastRemovedKey(profile.profilePartitionId))
            return SumiPermissionCleanupResult(
                removedCount: removedEvents.count,
                removedEvents: removedEvents,
                wasThrottled: false
            )
        } catch {
            _ = now()
            return SumiPermissionCleanupResult(
                removedCount: 0,
                removedEvents: [],
                wasThrottled: false
            )
        }
    }

    private func isCleanupEligible(
        _ record: SumiPermissionStoreRecord,
        now: Date,
        threshold: TimeInterval
    ) -> Bool {
        guard record.decision.persistence == .persistent,
              record.decision.state == .allow,
              record.key.permissionType.canBePersisted,
              cleanupPermissionTypesContain(record.key.permissionType)
        else {
            return false
        }
        let referenceDate = Self.staleReferenceDate(for: record.decision)
        return now.timeIntervalSince(referenceDate) >= threshold
    }

    private func cleanupPermissionTypesContain(_ permissionType: SumiPermissionType) -> Bool {
        switch permissionType {
        case .camera,
             .microphone,
             .geolocation,
             .notifications,
             .screenCapture,
             .popups,
             .externalScheme,
             .autoplay,
             .storageAccess:
            return true
        case .cameraAndMicrophone,
             .filePicker:
            return false
        }
    }

    private static func staleReferenceDate(for decision: SumiPermissionDecision) -> Date {
        decision.lastUsedAt ?? decision.updatedAt
    }

    private func lastRunKey(_ profilePartitionId: String) -> String {
        "\(Constants.lastRunPrefix).\(SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId))"
    }

    private func lastRemovedKey(_ profilePartitionId: String) -> String {
        "\(Constants.lastRemovedPrefix).\(SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId))"
    }
}
