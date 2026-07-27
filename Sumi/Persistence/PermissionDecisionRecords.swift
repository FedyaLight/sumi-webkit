import Foundation
import GRDB
import SumiDomain

struct PermissionDecisionRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "permission_decisions"

    let persistentIdentity: String
    let profileID: UUID
    var requestingOriginIdentity: String
    var topOriginIdentity: String
    var permissionTypeIdentity: String
    var profilePartitionID: String
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
    var metadata: Data?

    init(record: SumiPermissionStoreRecord) throws {
        guard let profileID = UUID(uuidString: record.key.profilePartitionId) else {
            throw SumiPermissionStoreError.invalidPersistentProfilePartition(
                record.key.profilePartitionId
            )
        }
        persistentIdentity = record.key.persistentIdentity
        self.profileID = profileID
        requestingOriginIdentity = record.key.requestingOrigin.identity
        topOriginIdentity = record.key.topOrigin.identity
        permissionTypeIdentity = record.key.permissionType.identity
        profilePartitionID = record.key.profilePartitionId
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
        metadata = try record.decision.metadata.map(JSONEncoder().encode)
    }

    func record() throws -> SumiPermissionStoreRecord {
        let canonicalProfileID = profileID.uuidString.lowercased()
        guard UUID(uuidString: profilePartitionID) == profileID else {
            throw SumiPermissionStoreError.invalidPersistentProfilePartition(
                profilePartitionID
            )
        }
        guard let permissionType = SumiPermissionType(identity: permissionTypeIdentity) else {
            throw SumiPermissionStoreError.invalidStoredPermissionType(
                permissionTypeIdentity
            )
        }
        let key = SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(identity: requestingOriginIdentity),
            topOrigin: SumiPermissionOrigin(identity: topOriginIdentity),
            permissionType: permissionType,
            profilePartitionId: canonicalProfileID,
            isEphemeralProfile: false
        )
        let decodedMetadata: [String: String]?
        do {
            decodedMetadata = try metadata.map {
                try JSONDecoder().decode([String: String].self, from: $0)
            }
        } catch {
            throw SumiPermissionStoreError.invalidMetadata
        }
        return SumiPermissionStoreRecord(
            key: key,
            decision: SumiPermissionDecision(
                state: SumiPermissionState(rawValue: stateRawValue) ?? .ask,
                persistence: SumiPermissionPersistence(rawValue: persistenceRawValue)
                    ?? .persistent,
                source: SumiPermissionDecisionSource(rawValue: sourceRawValue)
                    ?? .runtime,
                reason: reason,
                createdAt: createdAt,
                updatedAt: updatedAt,
                expiresAt: expiresAt,
                lastUsedAt: lastUsedAt,
                systemAuthorizationSnapshot: systemAuthorizationSnapshot,
                metadata: decodedMetadata
            ),
            displayDomain: displayDomain
        )
    }

    private enum CodingKeys: String, CodingKey {
        case persistentIdentity = "identity"
        case profileID = "profile_id"
        case profilePartitionID = "profile_partition_id"
        case requestingOriginIdentity = "requesting_origin"
        case topOriginIdentity = "top_origin"
        case permissionTypeIdentity = "permission_type"
        case displayDomain = "display_domain"
        case stateRawValue = "state"
        case persistenceRawValue = "persistence"
        case sourceRawValue = "source"
        case reason
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
        case lastUsedAt = "last_used_at"
        case systemAuthorizationSnapshot = "system_authorization"
        case metadata
    }
}

struct PermissionDecisionRecordStore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func find(identity: String) throws -> PermissionDecisionRow? {
        try PermissionDecisionRow.fetchOne(database, key: identity)
    }

    func all(profilePartitionID: String) throws -> [PermissionDecisionRow] {
        try PermissionDecisionRow
            .filter(Column("profile_partition_id") == profilePartitionID)
            .order(Column("display_domain"))
            .fetchAll(database)
    }

    func all(permissionType: String) throws -> [PermissionDecisionRow] {
        try PermissionDecisionRow
            .filter(Column("permission_type") == permissionType)
            .fetchAll(database)
    }

    func save(_ row: PermissionDecisionRow) throws {
        try row.save(database)
    }

    func delete(identity: String) throws {
        _ = try PermissionDecisionRow.deleteOne(database, key: identity)
    }

    func recordLastUsed(identity: String, at date: Date) throws {
        guard var row = try find(identity: identity) else { return }
        row.lastUsedAt = date
        try row.update(database)
    }
}
