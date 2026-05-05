import Foundation

enum SumiPermissionCleanupResult: Equatable, Sendable {
    case disabled
    case throttled
    case completed

    static func disabled(profilePartitionId: String, now: Date) -> Self {
        _ = profilePartitionId
        _ = now
        return .disabled
    }

    static func throttled(profilePartitionId: String, now: Date) -> Self {
        _ = profilePartitionId
        _ = now
        return .throttled
    }
}
