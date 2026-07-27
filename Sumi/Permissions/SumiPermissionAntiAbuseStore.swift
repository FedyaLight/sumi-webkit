import Foundation
import SumiDomain

protocol SumiPermissionAntiAbuseStoring: Sendable {
    func record(_ event: SumiPermissionAntiAbuseEvent) async
    func events(for key: SumiPermissionKey, now: Date) async -> [SumiPermissionAntiAbuseEvent]
    func clearSuppressionState(for key: SumiPermissionKey, now: Date) async
}

actor SumiPermissionAntiAbuseStore: SumiPermissionAntiAbuseStoring {
    private let retentionInterval: TimeInterval
    private let maximumEventsPerProfile: Int
    let persistenceAuthority: SumiPermissionPersistenceAuthority

    init(
        persistenceAuthority: SumiPermissionPersistenceAuthority,
        retentionInterval: TimeInterval = SumiPermissionPromptCooldown.eventRetention,
        maximumEventsPerProfile: Int = SumiPermissionPromptCooldown.maximumEventsPerProfile
    ) {
        self.persistenceAuthority = persistenceAuthority
        self.retentionInterval = retentionInterval
        self.maximumEventsPerProfile = max(1, maximumEventsPerProfile)
    }

    func record(_ event: SumiPermissionAntiAbuseEvent) async {
        persistenceAuthority.mutateAntiAbuseEvents { records in
            records.append(event)
            Self.prune(
                &records,
                now: event.createdAt,
                retentionInterval: retentionInterval,
                maximumEventsPerProfile: maximumEventsPerProfile
            )
        }
    }

    func events(for key: SumiPermissionKey, now: Date) async -> [SumiPermissionAntiAbuseEvent] {
        persistenceAuthority.mutateAntiAbuseEvents { records in
            Self.prune(
                &records,
                now: now,
                retentionInterval: retentionInterval,
                maximumEventsPerProfile: maximumEventsPerProfile
            )
            return records
                .filter {
                    $0.key.persistentIdentity == key.persistentIdentity
                        && $0.key.isEphemeralProfile == key.isEphemeralProfile
                }
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    func clearSuppressionState(for key: SumiPermissionKey, now: Date) async {
        persistenceAuthority.mutateAntiAbuseEvents { records in
            records.removeAll {
                $0.key.persistentIdentity == key.persistentIdentity
                    && $0.key.isEphemeralProfile == key.isEphemeralProfile
                    && Self.isSuppressionStateEvent($0.type)
            }
            Self.prune(
                &records,
                now: now,
                retentionInterval: retentionInterval,
                maximumEventsPerProfile: maximumEventsPerProfile
            )
        }
    }

    func diagnostics() -> SumiPermissionPersistenceDiagnostics {
        persistenceAuthority.persistenceDiagnostics
    }

    private static func prune(
        _ records: inout [SumiPermissionAntiAbuseEvent],
        now: Date,
        retentionInterval: TimeInterval,
        maximumEventsPerProfile: Int
    ) {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        records = records.filter { $0.createdAt >= cutoff }

        let grouped = Dictionary(grouping: records) { event in
            [
                event.key.profilePartitionId,
                event.key.isEphemeralProfile ? "ephemeral" : "persistent",
            ].joined(separator: "|")
        }
        records = grouped.values.flatMap { events in
            events
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(maximumEventsPerProfile)
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    private static func isSuppressionStateEvent(_ type: SumiPermissionAntiAbuseEvent.EventType) -> Bool {
        switch type {
        case .userDismissed,
             .userDenied,
             .requestSuppressedByCooldown,
             .requestSuppressedByEmbargo,
             .systemBlocked,
             .blockedByDefaultPolicy:
            return true
        case .promptShown,
             .userAllowed,
             .requestCancelledByNavigation,
             .autoRevokedByCleanup:
            return false
        }
    }
}
