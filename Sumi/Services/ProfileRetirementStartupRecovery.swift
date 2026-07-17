import Foundation

enum ProfileRetirementStartupPreflightStatus: Equatable {
    case ready
    case failed(message: String)

    var failureMessage: String? {
        guard case .failed(let message) = self else { return nil }
        return message
    }
}

enum ProfileRetirementStartupRecoveryError: Error, Equatable {
    case staleRecord(profileID: UUID, operation: String)
    case invalidPersistedPhase(profileID: UUID)
    case cleanupPreparationFailed(profileID: UUID)
    case referenceMigrationUnavailable(profileID: UUID)
    case referenceMigrationFailed(profileID: UUID)
}

extension ProfileRetirementStartupRecoveryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .staleRecord(let profileID, let operation):
            "Profile retirement recovery could not \(operation) for \(profileID.uuidString)."
        case .invalidPersistedPhase(let profileID):
            "Profile retirement recovery found an invalid completed record for \(profileID.uuidString)."
        case .cleanupPreparationFailed(let profileID):
            "Profile retirement recovery could not seal runtime data for \(profileID.uuidString)."
        case .referenceMigrationUnavailable(let profileID):
            "Profile retirement recovery could not resume reference migration for \(profileID.uuidString)."
        case .referenceMigrationFailed(let profileID):
            "Profile retirement recovery could not complete reference migration for \(profileID.uuidString)."
        }
    }
}

/// Completes durable profile retirement before the browser publishes its UI.
/// Reserved rows are cancelled synchronously by the composition root before
/// persisted tab restoration starts; the async pass owns destructive cleanup.
@MainActor
final class ProfileRetirementStartupRecovery {
    typealias CleanupFactory = @MainActor (
        ProfileRetirementSnapshot
    ) -> ProfileDeletionCleanupOrchestrator

    private let ledger: ProfileReferenceAdmissionLedger
    private let cleanupFactory: CleanupFactory
    private let migrateReferences: @MainActor (
        ProfileRetirementRecord
    ) async throws -> Void
    private let prepareCleanup: @MainActor (
        ProfileRetirementRecord
    ) async throws -> Void

    init(
        ledger: ProfileReferenceAdmissionLedger,
        migrateReferences: @escaping @MainActor (
            ProfileRetirementRecord
        ) async throws -> Void = { record in
            throw ProfileRetirementStartupRecoveryError
                .referenceMigrationUnavailable(
                    profileID: record.snapshot.id
                )
        },
        prepareCleanup: @escaping @MainActor (
            ProfileRetirementRecord
        ) async throws -> Void = { _ in },
        cleanupFactory: @escaping CleanupFactory
    ) {
        self.ledger = ledger
        self.migrateReferences = migrateReferences
        self.prepareCleanup = prepareCleanup
        self.cleanupFactory = cleanupFactory
    }

    static func cancelReservedReservations(
        in ledger: ProfileReferenceAdmissionLedger
    ) throws {
        for record in ledger.records() where record.phase == .reserved {
            guard try ledger.cancel(record.token) else {
                throw ProfileRetirementStartupRecoveryError.staleRecord(
                    profileID: record.snapshot.id,
                    operation: "cancel its pre-cleanup reservation"
                )
            }
        }
    }

    func recover() async throws {
        for initialRecord in ledger.records() {
            switch initialRecord.phase {
            case .reserved:
                guard try ledger.cancel(initialRecord.token) else {
                    throw ProfileRetirementStartupRecoveryError.staleRecord(
                        profileID: initialRecord.snapshot.id,
                        operation: "cancel its pre-cleanup reservation"
                    )
                }
            case .migratingReferences:
                try await migrateReferences(initialRecord)
                guard try ledger.commitLogicalDeletion(initialRecord.token),
                      let logicallyDeletedRecord = ledger.record(
                          for: initialRecord.token
                      )
                else {
                    throw ProfileRetirementStartupRecoveryError.staleRecord(
                        profileID: initialRecord.snapshot.id,
                        operation: "commit recovered logical deletion"
                    )
                }
                try await prepareCleanup(logicallyDeletedRecord)
                guard try ledger.beginCleaning(initialRecord.token),
                      let cleaningRecord = ledger.record(
                          for: initialRecord.token
                      )
                else {
                    throw ProfileRetirementStartupRecoveryError.staleRecord(
                        profileID: initialRecord.snapshot.id,
                        operation: "begin recovered cleanup"
                    )
                }
                try await resumeCleanup(cleaningRecord)
            case .logicallyDeleted:
                try await prepareCleanup(initialRecord)
                guard try ledger.beginCleaning(initialRecord.token),
                      let cleaningRecord = ledger.record(for: initialRecord.token)
                else {
                    throw ProfileRetirementStartupRecoveryError.staleRecord(
                        profileID: initialRecord.snapshot.id,
                        operation: "begin cleanup"
                    )
                }
                try await resumeCleanup(cleaningRecord)
            case .cleaning:
                try await prepareCleanup(initialRecord)
                try await resumeCleanup(initialRecord)
            case .retired:
                guard initialRecord.nextCleanupStep == .completed else {
                    throw ProfileRetirementStartupRecoveryError.invalidPersistedPhase(
                        profileID: initialRecord.snapshot.id
                    )
                }
                try await prepareCleanup(initialRecord)
            }
        }
    }

    private func resumeCleanup(_ record: ProfileRetirementRecord) async throws {
        let token = record.token
        let cleanup = cleanupFactory(record.snapshot)
        try await cleanup.cleanup(
            profileId: record.snapshot.id,
            startingAt: record.nextCleanupStep,
            checkpoint: { [ledger] completedStep in
                guard try ledger.completeCleanupStep(completedStep, using: token) else {
                    throw ProfileRetirementStartupRecoveryError.staleRecord(
                        profileID: record.snapshot.id,
                        operation: "checkpoint cleanup"
                    )
                }
            }
        )
        guard try ledger.markRetired(token) else {
            throw ProfileRetirementStartupRecoveryError.staleRecord(
                profileID: record.snapshot.id,
                operation: "finish cleanup"
            )
        }
    }
}
