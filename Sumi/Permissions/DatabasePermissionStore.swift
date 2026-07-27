import Foundation
import SumiDomain

actor DatabasePermissionStore: SumiPermissionStore {
    private let database: SumiDatabase

    init(database: SumiDatabase) {
        self.database = database
    }

    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord? {
        try database.read {
            try $0.permissions.find(identity: key.persistentIdentity)?.record()
        }
    }

    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async throws {
        try validatePersistentWrite(key: key, decision: decision)
        let record = SumiPermissionStoreRecord(key: key, decision: decision)
        try database.transaction {
            try $0.permissions.save(PermissionDecisionRow(record: record))
        }
    }

    func resetDecision(for key: SumiPermissionKey) async throws {
        try database.transaction {
            try $0.permissions.delete(identity: key.persistentIdentity)
        }
    }

    func listDecisions(profilePartitionId: String) async throws -> [SumiPermissionStoreRecord] {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return try database.read {
            try $0.permissions.all(profilePartitionID: profileId).map {
                try $0.record()
            }
        }
    }

    func recordLastUsed(for key: SumiPermissionKey, at date: Date) async throws {
        try database.transaction {
            try $0.permissions.recordLastUsed(
                identity: key.persistentIdentity,
                at: date
            )
        }
    }

    private func validatePersistentWrite(
        key: SumiPermissionKey,
        decision: SumiPermissionDecision
    ) throws {
        guard !key.isEphemeralProfile else {
            throw SumiPermissionStoreError.persistentWriteForEphemeralProfile
        }
        guard decision.persistence == .persistent else {
            throw SumiPermissionStoreError.unsupportedPersistence(decision.persistence)
        }
        guard UUID(uuidString: key.profilePartitionId) != nil else {
            throw SumiPermissionStoreError.invalidPersistentProfilePartition(
                key.profilePartitionId
            )
        }
        guard key.permissionType.canBePersisted else {
            throw SumiPermissionStoreError.unsupportedPersistentPermission(key.permissionType.identity)
        }
    }

}
