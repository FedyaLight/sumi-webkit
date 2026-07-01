import Foundation

enum SumiPermissionCleanupResult: Equatable, Sendable {
    case disabled
    case throttled
    case completed
    case failed(String)

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

    static func failed(_ error: any Error) -> Self {
        .failed(String(describing: error))
    }
}
