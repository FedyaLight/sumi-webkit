import Foundation
import SumiDomain

actor DatabasePermissionStore: SumiPermissionStore {
    private let database: SumiDatabase

    init(database: SumiDatabase) {
        self.database = database
    }

    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord? {
        let storageKey = SumiGlobalSitePermissionScope.storageKey(for: key)
        let record = try database.read {
            try $0.permissions.find(identity: storageKey.persistentIdentity)?.record()
        }
        return record.map { presentationRecord($0, for: key.profilePartitionId) }
    }

    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async throws {
        try validatePersistentRequest(key: key, decision: decision)
        let storageKey = SumiGlobalSitePermissionScope.storageKey(for: key)
        let record = SumiPermissionStoreRecord(key: storageKey, decision: decision)
        try database.transaction {
            try $0.permissions.save(PermissionDecisionRow(record: record))
        }
    }

    func resetDecision(for key: SumiPermissionKey) async throws {
        let storageKey = SumiGlobalSitePermissionScope.storageKey(for: key)
        try database.transaction {
            try $0.permissions.delete(identity: storageKey.persistentIdentity)
        }
    }

    func listDecisions(profilePartitionId: String) async throws -> [SumiPermissionStoreRecord] {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        let records = try database.read {
            try $0.permissions.all(
                profilePartitionID: SumiGlobalSitePermissionScope.profilePartitionId
            ).map { try $0.record() }
        }
        return records.map {
            presentationRecord($0, for: profileId)
        }
    }

    func recordLastUsed(for key: SumiPermissionKey, at date: Date) async throws {
        let storageKey = SumiGlobalSitePermissionScope.storageKey(for: key)
        try database.transaction {
            try $0.permissions.recordLastUsed(
                identity: storageKey.persistentIdentity,
                at: date
            )
        }
    }

    private func validatePersistentRequest(
        key: SumiPermissionKey,
        decision: SumiPermissionDecision
    ) throws {
        guard !key.isEphemeralProfile else {
            throw SumiPermissionStoreError.persistentWriteForEphemeralProfile
        }
        guard decision.persistence == .persistent else {
            throw SumiPermissionStoreError.unsupportedPersistence(decision.persistence)
        }
        guard SumiGlobalSitePermissionScope.isGlobal(key)
                || UUID(uuidString: key.profilePartitionId) != nil
        else {
            throw SumiPermissionStoreError.invalidPersistentProfilePartition(
                key.profilePartitionId
            )
        }
        guard key.permissionType.canBePersisted else {
            throw SumiPermissionStoreError.unsupportedPersistentPermission(key.permissionType.identity)
        }
    }

    private func presentationRecord(
        _ record: SumiPermissionStoreRecord,
        for profilePartitionId: String
    ) -> SumiPermissionStoreRecord {
        SumiPermissionStoreRecord(
            key: SumiGlobalSitePermissionScope.presentationKey(
                for: record.key,
                profilePartitionId: profilePartitionId
            ),
            decision: record.decision,
            displayDomain: record.displayDomain
        )
    }

}
