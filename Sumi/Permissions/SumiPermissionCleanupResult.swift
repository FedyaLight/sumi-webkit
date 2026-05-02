import Foundation

struct SumiPermissionCleanupResult: Equatable, Sendable {
    let removedCount: Int
    let removedEvents: [SumiPermissionAutoRevokedEvent]
    let wasThrottled: Bool

    static func disabled(profilePartitionId: String, now: Date) -> Self {
        _ = profilePartitionId
        _ = now
        return SumiPermissionCleanupResult(
            removedCount: 0,
            removedEvents: [],
            wasThrottled: false
        )
    }

    static func throttled(profilePartitionId: String, now: Date) -> Self {
        _ = profilePartitionId
        _ = now
        return SumiPermissionCleanupResult(
            removedCount: 0,
            removedEvents: [],
            wasThrottled: true
        )
    }
}
