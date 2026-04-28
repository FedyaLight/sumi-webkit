import Foundation

struct SumiPermissionStoreRecord: Codable, Equatable, Hashable, Sendable {
    let key: SumiPermissionKey
    let decision: SumiPermissionDecision
    let displayDomain: String

    init(
        key: SumiPermissionKey,
        decision: SumiPermissionDecision,
        displayDomain: String? = nil
    ) {
        self.key = key
        self.decision = decision
        self.displayDomain = Self.normalizedDisplayDomain(displayDomain ?? key.displayDomain)
    }

    static func normalizedDisplayDomain(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Origin" : trimmed.lowercased()
    }
}

enum SumiPermissionStoreError: Error, Equatable, LocalizedError {
    case persistentWriteForEphemeralProfile
    case unsupportedPersistence(SumiPermissionPersistence)
    case unsupportedPersistentPermission(String)
    case oneTimeDecisionRequiresPageId
    case invalidStoredPermissionType(String)
    case invalidMetadata

    var errorDescription: String? {
        switch self {
        case .persistentWriteForEphemeralProfile:
            return "Persistent permission decisions cannot be written for ephemeral profiles."
        case .unsupportedPersistence(let persistence):
            return "Unsupported permission decision persistence: \(persistence.rawValue)."
        case .unsupportedPersistentPermission(let permissionIdentity):
            return "Permission type cannot be persisted directly: \(permissionIdentity)."
        case .oneTimeDecisionRequiresPageId:
            return "One-time permission decisions require a transient page id."
        case .invalidStoredPermissionType(let identity):
            return "Stored permission type is invalid: \(identity)."
        case .invalidMetadata:
            return "Permission decision metadata could not be encoded or decoded."
        }
    }
}

protocol SumiPermissionStore: Sendable {
    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord?
    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async throws
    func resetDecision(for key: SumiPermissionKey) async throws
    func listDecisions(profilePartitionId: String) async throws -> [SumiPermissionStoreRecord]
    func listDecisions(
        forDisplayDomain displayDomain: String,
        profilePartitionId: String
    ) async throws -> [SumiPermissionStoreRecord]
    func clearAll(profilePartitionId: String) async throws
    func clearForDisplayDomains(
        _ displayDomains: Set<String>,
        profilePartitionId: String
    ) async throws
    func clearForOrigins(
        _ origins: Set<SumiPermissionOrigin>,
        profilePartitionId: String
    ) async throws
    @discardableResult
    func expireDecisions(now: Date) async throws -> Int
    func recordLastUsed(for key: SumiPermissionKey, at date: Date) async throws
}
