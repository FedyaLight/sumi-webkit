//
//  ProfileReferenceAdmissionLedger.swift
//  Sumi
//

import Foundation

struct ProfileReferenceAdmissionReceipt: Equatable, Hashable, Sendable {
    let profileID: UUID
    let revision: UInt64

    fileprivate init(profileID: UUID, revision: UInt64) {
        self.profileID = profileID
        self.revision = revision
    }
}

struct ProfileReferenceMutationLease: Equatable, Sendable {
    fileprivate let generation: UUID
    fileprivate let scope: UUID
    fileprivate let receipts: [ProfileReferenceAdmissionReceipt]
}

enum ProfileReferenceAdmissionLedgerError: Error, Equatable {
    case unavailable
    case referenceBlocked(UUID)
    case retirementInProgress(UUID)
    case retirementMigrationUnavailable
    case retirementMigrationTargetMismatch(
        expected: UUID,
        requested: Set<UUID>
    )
    case mutationInProgress
}

@MainActor
final class ProfileReferenceAdmissionLedger {
    private enum MutationKind {
        case references
        case retirementMigration
    }

    private struct ActiveMutation {
        let generation: UUID
        let kind: MutationKind
        var scopes: [UUID: [ProfileReferenceAdmissionReceipt]]
    }

    private let store: ProfileRetirementStore?
    private let allowsReferencesWithoutStore: Bool
    private var retirementByProfileID: [UUID: ProfileRetirementRecord]
    private var quarantinedRetirementByProfileID: [UUID: ProfileRetirementQuarantine]
    private var admissionRevisionByProfileID: [UUID: UInt64] = [:]
    private var activeMutation: ActiveMutation?
    private var allowsUnrelatedReferencesDuringDeferredRecovery = false

    init(store: ProfileRetirementStore) throws {
        self.store = store
        allowsReferencesWithoutStore = false
        let loadResult = try store.loadForAdmission()
        self.retirementByProfileID = Dictionary(
            uniqueKeysWithValues: loadResult.records.map { ($0.snapshot.id, $0) }
        )
        self.quarantinedRetirementByProfileID = Dictionary(
            uniqueKeysWithValues: loadResult.quarantined.map { ($0.profileID, $0) }
        )
    }

    convenience init(database: SumiDatabase) throws {
        try self.init(store: ProfileRetirementStore(database: database))
    }

    private init() {
        self.store = nil
        allowsReferencesWithoutStore = false
        self.retirementByProfileID = [:]
        self.quarantinedRetirementByProfileID = [:]
    }

    #if DEBUG
        private init(testingAllowsReferences: Bool) {
            store = nil
            allowsReferencesWithoutStore = testingAllowsReferences
            retirementByProfileID = [:]
            quarantinedRetirementByProfileID = [:]
        }

        static func testingAllowingReferences() -> ProfileReferenceAdmissionLedger {
            ProfileReferenceAdmissionLedger(testingAllowsReferences: true)
        }
    #endif

    static func failClosed() -> ProfileReferenceAdmissionLedger {
        ProfileReferenceAdmissionLedger()
    }

    var isAvailable: Bool { store != nil || allowsReferencesWithoutStore }

    func records() -> [ProfileRetirementRecord] {
        retirementByProfileID.values.sorted {
            $0.snapshot.index < $1.snapshot.index
        }
    }

    var quarantinedRetirements: [ProfileRetirementQuarantine] {
        quarantinedRetirementByProfileID.values.sorted {
            $0.profileID.uuidString < $1.profileID.uuidString
        }
    }

    var blockedProfileIDs: Set<UUID> {
        Set(retirementByProfileID.keys).union(quarantinedRetirementByProfileID.keys)
    }

    func record(for token: ProfileRetirementToken) -> ProfileRetirementRecord? {
        guard let record = retirementByProfileID[token.profileID],
              record.token == token
        else {
            return nil
        }
        return record
    }

    func isReferenceAllowed(_ profileID: UUID) -> Bool {
        (store != nil || allowsReferencesWithoutStore)
            && blockedProfileIDs.contains(profileID) == false
    }

    func admitReference(to profileID: UUID) -> ProfileReferenceAdmissionReceipt? {
        guard isReferenceAllowed(profileID) else { return nil }
        return ProfileReferenceAdmissionReceipt(
            profileID: profileID,
            revision: admissionRevisionByProfileID[profileID, default: 0]
        )
    }

    func validate(_ receipt: ProfileReferenceAdmissionReceipt) -> Bool {
        isReferenceAllowed(receipt.profileID)
            && admissionRevisionByProfileID[receipt.profileID, default: 0] == receipt.revision
    }

    func validate(_ token: ProfileRetirementToken) -> Bool {
        record(for: token) != nil
    }

    func beginReferenceMutation(
        to profileIDs: Set<UUID>
    ) throws -> ProfileReferenceMutationLease {
        try beginReferenceMutation(
            to: profileIDs,
            requiresQuiescentRetirement: true
        )
    }

    func beginRetirementReferenceMigration(
        to profileIDs: Set<UUID>
    ) throws -> ProfileReferenceMutationLease {
        let activeRetirements = retirementByProfileID.values.filter {
            $0.phase != .retired
        }
        if activeRetirements.isEmpty,
           quarantinedRetirementByProfileID.isEmpty == false,
           profileIDs.count == 1,
           profileIDs.allSatisfy(isReferenceAllowed) {
            return try beginReferenceMutation(
                to: profileIDs,
                requiresQuiescentRetirement: false
            )
        }
        guard activeRetirements.count == 1,
              let retirement = activeRetirements.first,
              retirement.phase == .migratingReferences else {
            throw ProfileReferenceAdmissionLedgerError.retirementMigrationUnavailable
        }
        let exactFallback = Set([retirement.fallbackProfileID])
        guard profileIDs == exactFallback else {
            throw ProfileReferenceAdmissionLedgerError
                .retirementMigrationTargetMismatch(
                    expected: retirement.fallbackProfileID,
                    requested: profileIDs
                )
        }
        return try beginReferenceMutation(
            to: profileIDs,
            requiresQuiescentRetirement: false
        )
    }

    private func beginReferenceMutation(
        to profileIDs: Set<UUID>,
        requiresQuiescentRetirement: Bool
    ) throws -> ProfileReferenceMutationLease {
        guard store != nil || allowsReferencesWithoutStore else {
            throw ProfileReferenceAdmissionLedgerError.unavailable
        }
        if var activeMutation {
            guard requiresQuiescentRetirement,
                  activeMutation.kind == .references else {
                throw ProfileReferenceAdmissionLedgerError.mutationInProgress
            }
            let receipts = try profileIDs.sorted(by: uuidOrder).map { profileID in
                guard let receipt = admitReference(to: profileID) else {
                    throw ProfileReferenceAdmissionLedgerError
                        .referenceBlocked(profileID)
                }
                return receipt
            }
            let scope = UUID()
            activeMutation.scopes[scope] = receipts
            self.activeMutation = activeMutation
            return ProfileReferenceMutationLease(
                generation: activeMutation.generation,
                scope: scope,
                receipts: receipts
            )
        }
        if requiresQuiescentRetirement,
           allowsUnrelatedReferencesDuringDeferredRecovery == false,
           let profileID = activeRetirementProfileID {
            throw ProfileReferenceAdmissionLedgerError.retirementInProgress(
                profileID
            )
        }
        let receipts = try profileIDs.sorted(by: uuidOrder).map { profileID in
            guard let receipt = admitReference(to: profileID) else {
                throw ProfileReferenceAdmissionLedgerError.referenceBlocked(
                    profileID
                )
            }
            return receipt
        }
        let generation = UUID()
        let scope = UUID()
        activeMutation = ActiveMutation(
            generation: generation,
            kind: requiresQuiescentRetirement
                ? .references
                : .retirementMigration,
            scopes: [scope: receipts]
        )
        return ProfileReferenceMutationLease(
            generation: generation,
            scope: scope,
            receipts: receipts
        )
    }

    func allowUnrelatedReferencesDuringDeferredRecovery() {
        allowsUnrelatedReferencesDuringDeferredRecovery = true
    }

    private var activeRetirementProfileID: UUID? {
        if let retirement = retirementByProfileID.values.first(where: {
            $0.phase != .retired
        }) {
            return retirement.snapshot.id
        }
        return quarantinedRetirementByProfileID.keys.first
    }

    func validate(_ lease: ProfileReferenceMutationLease) -> Bool {
        guard let activeMutation,
              activeMutation.generation == lease.generation,
              activeMutation.scopes[lease.scope] == lease.receipts else {
            return false
        }
        return lease.receipts.allSatisfy(validate)
    }

    func validate(
        _ lease: ProfileReferenceMutationLease,
        covers profileIDs: Set<UUID>
    ) -> Bool {
        validate(lease)
            && Set(lease.receipts.map(\.profileID)).isSuperset(of: profileIDs)
    }

    func endReferenceMutation(_ lease: ProfileReferenceMutationLease) -> Bool {
        guard var activeMutation,
              activeMutation.generation == lease.generation,
              activeMutation.scopes.removeValue(forKey: lease.scope) != nil else {
            return false
        }
        self.activeMutation = activeMutation.scopes.isEmpty
            ? nil
            : activeMutation
        return true
    }

    func reserve(
        profile: Profile,
        fallbackID: UUID
    ) throws -> ProfileRetirementToken {
        guard let store else {
            throw ProfileReferenceAdmissionLedgerError.unavailable
        }
        guard activeMutation == nil else {
            throw ProfileReferenceAdmissionLedgerError.mutationInProgress
        }
        let generation = UUID()
        let record = try store.reserve(
            profileID: profile.id,
            fallbackProfileID: fallbackID,
            generation: generation
        )
        retirementByProfileID[profile.id] = record
        invalidateAdmissions(for: profile.id)
        return record.token
    }

    func commitLogicalDeletion(_ token: ProfileRetirementToken) throws -> Bool {
        guard let store else {
            throw ProfileReferenceAdmissionLedgerError.unavailable
        }
        guard validate(token),
              try store.commitLogicalDeletion(token)
        else {
            return false
        }
        return try reload(token)
    }

    func beginReferenceMigration(_ token: ProfileRetirementToken) throws -> Bool {
        guard let store else {
            throw ProfileReferenceAdmissionLedgerError.unavailable
        }
        guard validate(token), try store.beginReferenceMigration(token) else {
            return false
        }
        return try reload(token)
    }

    func retargetFallback(
        _ token: ProfileRetirementToken,
        to fallbackProfileID: UUID
    ) throws -> Bool {
        guard let store else {
            throw ProfileReferenceAdmissionLedgerError.unavailable
        }
        guard validate(token),
              try store.retargetFallback(token, to: fallbackProfileID)
        else {
            return false
        }
        return try reload(token)
    }

    func beginCleaning(_ token: ProfileRetirementToken) throws -> Bool {
        guard let store else {
            throw ProfileReferenceAdmissionLedgerError.unavailable
        }
        guard validate(token), try store.beginCleaning(token) else { return false }
        return try reload(token)
    }

    func completeCleanupStep(
        _ completedStep: ProfileRetirementCleanupStep,
        using token: ProfileRetirementToken
    ) throws -> Bool {
        guard let store else {
            throw ProfileReferenceAdmissionLedgerError.unavailable
        }
        guard validate(token),
              try store.completeCleanupStep(completedStep, using: token)
        else {
            return false
        }
        return try reload(token)
    }

    func checkpointCleanup(
        nextStep: ProfileRetirementCleanupStep,
        using token: ProfileRetirementToken
    ) throws -> Bool {
        guard let store else {
            throw ProfileReferenceAdmissionLedgerError.unavailable
        }
        guard validate(token),
              try store.checkpointCleanup(nextStep: nextStep, using: token)
        else {
            return false
        }
        return try reload(token)
    }

    func markRetired(_ token: ProfileRetirementToken) throws -> Bool {
        guard let store else {
            throw ProfileReferenceAdmissionLedgerError.unavailable
        }
        guard validate(token), try store.markRetired(token) else { return false }
        guard try reload(token) else { return false }
        invalidateAdmissions(for: token.profileID)
        return true
    }

    func cancel(_ token: ProfileRetirementToken) throws -> Bool {
        guard let store else {
            throw ProfileReferenceAdmissionLedgerError.unavailable
        }
        guard validate(token), try store.cancel(token) else { return false }
        retirementByProfileID[token.profileID] = nil
        invalidateAdmissions(for: token.profileID)
        return true
    }

    private func reload(_ token: ProfileRetirementToken) throws -> Bool {
        guard let store else {
            throw ProfileReferenceAdmissionLedgerError.unavailable
        }
        guard let record = try store.record(for: token) else {
            retirementByProfileID[token.profileID] = nil
            return false
        }
        retirementByProfileID[token.profileID] = record
        return true
    }

    private func invalidateAdmissions(for profileID: UUID) {
        admissionRevisionByProfileID[profileID, default: 0] += 1
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
