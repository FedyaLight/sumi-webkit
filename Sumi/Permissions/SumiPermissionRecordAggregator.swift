import Foundation
import SumiDomain

/// Owns cross-store permission record aggregation: merging coordinator and
/// autoplay site decisions, and folding recent activity, blocked popups,
/// external scheme attempts, and indicator events into one activity stream.
@MainActor
final class SumiPermissionRecordAggregator {
    private let coordinator: any SumiPermissionCoordinating
    private let autoplayStore: SumiAutoplayPolicyStoreAdapter
    private let recentActivityStore: SumiPermissionRecentActivityStore
    private let blockedPopupStore: SumiBlockedPopupStore
    private let externalSchemeSessionStore: SumiExternalSchemeSessionStore
    private let indicatorEventStore: SumiPermissionIndicatorEventStore
    private let now: () -> Date

    init(
        coordinator: any SumiPermissionCoordinating,
        autoplayStore: SumiAutoplayPolicyStoreAdapter,
        recentActivityStore: SumiPermissionRecentActivityStore,
        blockedPopupStore: SumiBlockedPopupStore,
        externalSchemeSessionStore: SumiExternalSchemeSessionStore,
        indicatorEventStore: SumiPermissionIndicatorEventStore,
        now: @escaping () -> Date
    ) {
        self.coordinator = coordinator
        self.autoplayStore = autoplayStore
        self.recentActivityStore = recentActivityStore
        self.blockedPopupStore = blockedPopupStore
        self.externalSchemeSessionStore = externalSchemeSessionStore
        self.indicatorEventStore = indicatorEventStore
        self.now = now
    }

    func permissionRecords(
        profile: SumiPermissionSettingsProfileContext
    ) async throws -> [SumiPermissionStoreRecord] {
        let coordinatorRecords = try await coordinator.siteDecisionRecords(
            profilePartitionId: profile.profilePartitionId,
            isEphemeralProfile: profile.isEphemeralProfile
        )
        let autoplayRecords = try await autoplayStore.siteDecisionRecords(
            profilePartitionId: profile.profilePartitionId,
            isEphemeralProfile: profile.isEphemeralProfile
        )
        return Self.deduplicated(records: coordinatorRecords + autoplayRecords)
            .filter { $0.decision.persistence == .persistent }
    }

    func recentRecords(
        profile: SumiPermissionSettingsProfileContext
    ) -> [SumiPermissionRecentActivityRecord] {
        let normalizedProfileId = profile.profilePartitionId
        var records = recentActivityStore.records(
            profilePartitionId: normalizedProfileId,
            isEphemeralProfile: profile.isEphemeralProfile,
            limit: 100
        )

        records.append(contentsOf: blockedPopupStore.allRecords().compactMap { record in
            guard record.profilePartitionId == normalizedProfileId,
                  record.isEphemeralProfile == profile.isEphemeralProfile
            else { return nil }
            return SumiPermissionRecentActivityRecord(
                id: record.id,
                displayDomain: record.requestingOrigin.displayDomain,
                requestingOrigin: record.requestingOrigin,
                topOrigin: record.topOrigin,
                profilePartitionId: record.profilePartitionId,
                isEphemeralProfile: record.isEphemeralProfile,
                permissionType: .popups,
                action: .blockedPopup,
                createdAt: record.lastBlockedAt,
                count: record.attemptCount
            )
        })

        records.append(contentsOf: externalSchemeSessionStore.allRecords().compactMap { record in
            guard record.profilePartitionId == normalizedProfileId,
                  record.isEphemeralProfile == profile.isEphemeralProfile
            else { return nil }
            return SumiPermissionRecentActivityRecord(
                id: record.id,
                displayDomain: record.requestingOrigin.displayDomain,
                requestingOrigin: record.requestingOrigin,
                topOrigin: record.topOrigin,
                profilePartitionId: record.profilePartitionId,
                isEphemeralProfile: record.isEphemeralProfile,
                permissionType: .externalScheme(record.scheme),
                action: record.result == .opened ? .openedExternalApp : .blocked,
                createdAt: record.lastAttemptAt,
                count: record.attemptCount
            )
        })

        records.append(contentsOf: indicatorRecords(profile: profile).compactMap { record in
            guard let requestingOrigin = record.requestingOrigin,
                  let topOrigin = record.topOrigin
            else { return nil }
            let action: SumiPermissionRecentActivityRecord.Action = record.category == .systemBlocked
                ? .systemBlocked
                : .blocked
            return SumiPermissionRecentActivityRecord(
                id: record.id,
                displayDomain: record.displayDomain,
                requestingOrigin: requestingOrigin,
                topOrigin: topOrigin,
                profilePartitionId: record.profilePartitionId,
                isEphemeralProfile: record.isEphemeralProfile,
                permissionType: record.primaryPermissionType,
                action: action,
                createdAt: record.createdAt,
                count: record.attemptCount
            )
        })

        return records.sorted { $0.createdAt > $1.createdAt }
    }

    func indicatorRecords(
        profile: SumiPermissionSettingsProfileContext
    ) -> [SumiPermissionIndicatorEventRecord] {
        indicatorEventStore.allRecords(now: now()).filter {
            $0.profilePartitionId == profile.profilePartitionId
                && $0.isEphemeralProfile == profile.isEphemeralProfile
        }
    }

    func isRecord(_ record: SumiPermissionStoreRecord, in scope: SumiPermissionSiteScope) -> Bool {
        record.key.profilePartitionId == scope.profilePartitionId
            && record.key.isEphemeralProfile == scope.isEphemeralProfile
            && record.key.requestingOrigin.identity == scope.requestingOrigin.identity
            && record.key.topOrigin.identity == scope.topOrigin.identity
    }

    private static func deduplicated(
        records: [SumiPermissionStoreRecord]
    ) -> [SumiPermissionStoreRecord] {
        var byIdentity: [String: SumiPermissionStoreRecord] = [:]
        for record in records {
            byIdentity[record.key.persistentIdentity] = record
        }
        return Array(byIdentity.values)
    }
}
