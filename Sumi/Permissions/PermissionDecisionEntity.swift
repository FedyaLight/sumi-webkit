import Foundation
import SwiftData

@Model
final class PermissionDecisionEntity {
    #Index<PermissionDecisionEntity>(
        [\.persistentIdentity],
        [\.profilePartitionId],
        [\.profilePartitionId, \.displayDomain],
        [\.profilePartitionId, \.permissionTypeIdentity],
        [\.requestingOriginIdentity],
        [\.topOriginIdentity]
    )

    @Attribute(.unique) var persistentIdentity: String
    var requestingOriginIdentity: String
    var topOriginIdentity: String
    var permissionTypeIdentity: String
    var profilePartitionId: String
    var displayDomain: String

    var stateRawValue: String
    var persistenceRawValue: String
    var sourceRawValue: String
    var reason: String?
    var createdAt: Date
    var updatedAt: Date
    var expiresAt: Date?
    var lastUsedAt: Date?
    var systemAuthorizationSnapshot: String?
    var metadataJSON: String?

    init(record: SumiPermissionStoreRecord) throws {
        self.persistentIdentity = record.key.persistentIdentity
        self.requestingOriginIdentity = record.key.requestingOrigin.identity
        self.topOriginIdentity = record.key.topOrigin.identity
        self.permissionTypeIdentity = record.key.permissionType.identity
        self.profilePartitionId = record.key.profilePartitionId
        self.displayDomain = record.displayDomain
        self.stateRawValue = record.decision.state.rawValue
        self.persistenceRawValue = record.decision.persistence.rawValue
        self.sourceRawValue = record.decision.source.rawValue
        self.reason = record.decision.reason
        self.createdAt = record.decision.createdAt
        self.updatedAt = record.decision.updatedAt
        self.expiresAt = record.decision.expiresAt
        self.lastUsedAt = record.decision.lastUsedAt
        self.systemAuthorizationSnapshot = record.decision.systemAuthorizationSnapshot
        self.metadataJSON = try Self.encodeMetadata(record.decision.metadata)
    }

    func update(with record: SumiPermissionStoreRecord) throws {
        requestingOriginIdentity = record.key.requestingOrigin.identity
        topOriginIdentity = record.key.topOrigin.identity
        permissionTypeIdentity = record.key.permissionType.identity
        profilePartitionId = record.key.profilePartitionId
        displayDomain = record.displayDomain
        stateRawValue = record.decision.state.rawValue
        persistenceRawValue = record.decision.persistence.rawValue
        sourceRawValue = record.decision.source.rawValue
        reason = record.decision.reason
        createdAt = record.decision.createdAt
        updatedAt = record.decision.updatedAt
        expiresAt = record.decision.expiresAt
        lastUsedAt = record.decision.lastUsedAt
        systemAuthorizationSnapshot = record.decision.systemAuthorizationSnapshot
        metadataJSON = try Self.encodeMetadata(record.decision.metadata)
    }

    func record() throws -> SumiPermissionStoreRecord {
        guard let permissionType = SumiPermissionType(identity: permissionTypeIdentity) else {
            throw SumiPermissionStoreError.invalidStoredPermissionType(permissionTypeIdentity)
        }
        let key = SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(identity: requestingOriginIdentity),
            topOrigin: SumiPermissionOrigin(identity: topOriginIdentity),
            permissionType: permissionType,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: false
        )
        let decision = SumiPermissionDecision(
            state: SumiPermissionState(rawValue: stateRawValue) ?? .ask,
            persistence: SumiPermissionPersistence(rawValue: persistenceRawValue) ?? .persistent,
            source: SumiPermissionDecisionSource(rawValue: sourceRawValue) ?? .runtime,
            reason: reason,
            createdAt: createdAt,
            updatedAt: updatedAt,
            expiresAt: expiresAt,
            lastUsedAt: lastUsedAt,
            systemAuthorizationSnapshot: systemAuthorizationSnapshot,
            metadata: try Self.decodeMetadata(metadataJSON)
        )
        return SumiPermissionStoreRecord(
            key: key,
            decision: decision,
            displayDomain: displayDomain
        )
    }

    private static func encodeMetadata(_ metadata: [String: String]?) throws -> String? {
        guard let metadata else { return nil }
        do {
            let data = try JSONEncoder().encode(metadata)
            return String(data: data, encoding: .utf8)
        } catch {
            throw SumiPermissionStoreError.invalidMetadata
        }
    }

    private static func decodeMetadata(_ metadataJSON: String?) throws -> [String: String]? {
        guard let metadataJSON else { return nil }
        guard let data = metadataJSON.data(using: .utf8) else {
            throw SumiPermissionStoreError.invalidMetadata
        }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw SumiPermissionStoreError.invalidMetadata
        }
    }
}
