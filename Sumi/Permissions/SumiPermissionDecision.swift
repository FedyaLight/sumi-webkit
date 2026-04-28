import Foundation

struct SumiPermissionDecision: Codable, Equatable, Hashable, Sendable {
    var state: SumiPermissionState
    var persistence: SumiPermissionPersistence
    var source: SumiPermissionDecisionSource
    var reason: String?
    var createdAt: Date
    var updatedAt: Date
    var expiresAt: Date?
    var lastUsedAt: Date?
    var systemAuthorizationSnapshot: String?
    var metadata: [String: String]?

    init(
        state: SumiPermissionState,
        persistence: SumiPermissionPersistence,
        source: SumiPermissionDecisionSource,
        reason: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        expiresAt: Date? = nil,
        lastUsedAt: Date? = nil,
        systemAuthorizationSnapshot: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.state = state
        self.persistence = persistence
        self.source = source
        self.reason = reason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.lastUsedAt = lastUsedAt
        self.systemAuthorizationSnapshot = systemAuthorizationSnapshot
        self.metadata = metadata
    }

    func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    func recordingLastUsed(at date: Date) -> Self {
        var copy = self
        copy.lastUsedAt = date
        return copy
    }
}
