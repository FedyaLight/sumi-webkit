import Foundation
import SwiftData

actor SwiftDataPermissionStore: SumiPermissionStore {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord? {
        let context = makeContext()
        return try fetchEntity(for: key, in: context)?.record()
    }

    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async throws {
        try validatePersistentWrite(key: key, decision: decision)
        let context = makeContext()
        let record = SumiPermissionStoreRecord(key: key, decision: decision)
        if let entity = try fetchEntity(for: key, in: context) {
            try entity.update(with: record)
        } else {
            context.insert(try PermissionDecisionEntity(record: record))
        }
        try context.save()
    }

    func resetDecision(for key: SumiPermissionKey) async throws {
        let context = makeContext()
        if let entity = try fetchEntity(for: key, in: context) {
            context.delete(entity)
            try context.save()
        }
    }

    func listDecisions(profilePartitionId: String) async throws -> [SumiPermissionStoreRecord] {
        let context = makeContext()
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        let predicate = #Predicate<PermissionDecisionEntity> { entity in
            entity.profilePartitionId == profileId
        }
        let descriptor = FetchDescriptor<PermissionDecisionEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.displayDomain, order: .forward)]
        )
        return try context.fetch(descriptor).map { try $0.record() }
    }

    func recordLastUsed(for key: SumiPermissionKey, at date: Date) async throws {
        let context = makeContext()
        guard let entity = try fetchEntity(for: key, in: context) else { return }
        entity.lastUsedAt = date
        try context.save()
    }

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
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
        guard key.permissionType.canBePersisted else {
            throw SumiPermissionStoreError.unsupportedPersistentPermission(key.permissionType.identity)
        }
    }

    private func fetchEntity(
        for key: SumiPermissionKey,
        in context: ModelContext
    ) throws -> PermissionDecisionEntity? {
        let identity = key.persistentIdentity
        let predicate = #Predicate<PermissionDecisionEntity> { entity in
            entity.persistentIdentity == identity
        }
        var descriptor = FetchDescriptor<PermissionDecisionEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
