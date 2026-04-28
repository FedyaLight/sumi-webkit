import Foundation

struct SumiPermissionAntiAbuseEvent: Codable, Equatable, Identifiable, Sendable {
    enum EventType: String, Codable, CaseIterable, Hashable, Sendable {
        case promptShown
        case userAllowed
        case userDenied
        case userDismissed
        case requestCancelledByNavigation
        case requestSuppressedByCooldown
        case requestSuppressedByEmbargo
        case systemBlocked
        case blockedByDefaultPolicy
        case autoRevokedByCleanup
    }

    let id: String
    let type: EventType
    let key: SumiPermissionKey
    let createdAt: Date
    let reason: String?

    init(
        id: String = UUID().uuidString,
        type: EventType,
        key: SumiPermissionKey,
        createdAt: Date = Date(),
        reason: String? = nil
    ) {
        self.id = id
        self.type = type
        self.key = key
        self.createdAt = createdAt
        self.reason = reason
    }

    var profilePartitionId: String {
        key.profilePartitionId
    }
}
