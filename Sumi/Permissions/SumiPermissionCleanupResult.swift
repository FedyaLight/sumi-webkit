import Foundation

struct SumiPermissionCleanupResult: Equatable, Sendable {
    let profilePartitionId: String
    let startedAt: Date
    let finishedAt: Date
    let scannedCount: Int
    let removedCount: Int
    let retainedCount: Int
    let skippedCount: Int
    let removedEvents: [SumiPermissionAutoRevokedEvent]
    let wasThrottled: Bool
    let errorMessage: String?

    static func disabled(profilePartitionId: String, now: Date) -> Self {
        SumiPermissionCleanupResult(
            profilePartitionId: SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId),
            startedAt: now,
            finishedAt: now,
            scannedCount: 0,
            removedCount: 0,
            retainedCount: 0,
            skippedCount: 0,
            removedEvents: [],
            wasThrottled: false,
            errorMessage: nil
        )
    }

    static func throttled(profilePartitionId: String, now: Date) -> Self {
        SumiPermissionCleanupResult(
            profilePartitionId: SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId),
            startedAt: now,
            finishedAt: now,
            scannedCount: 0,
            removedCount: 0,
            retainedCount: 0,
            skippedCount: 0,
            removedEvents: [],
            wasThrottled: true,
            errorMessage: nil
        )
    }
}
