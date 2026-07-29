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
    case cleanupDeferred(profileID: UUID, reason: String)
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
        case .cleanupDeferred(let profileID, let reason):
            "Profile retirement cleanup remains pending for \(profileID.uuidString): \(reason)"
        }
    }
}

struct ProfileRetirementRecoveryIssue: Equatable, Sendable {
    enum Kind: String, Sendable {
        case quarantinedRecord
        case referenceMigration
        case logicalDeletion
        case cleanup
    }

    let profileID: UUID
    let phase: String
    let kind: Kind
    let reason: String
    let requiresReferenceSanitization: Bool
}

struct ProfileRetirementStartupRecoveryReport: Equatable, Sendable {
    var issues: [ProfileRetirementRecoveryIssue] = []

    var hasDeferredRecovery: Bool { issues.isEmpty == false }

    var profileIDsRequiringReferenceSanitization: Set<UUID> {
        Set(
            issues.lazy
                .filter(\.requiresReferenceSanitization)
                .map(\.profileID)
        )
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
    private let prepareRuntimeRetirement: @MainActor (
        ProfileRetirementRecord
    ) async throws -> Void
    private let rehydrateRetirementState: @MainActor (
        ProfileRetirementRecord
    ) async throws -> Void
    private let sanitizeDeferredReferences: @MainActor (
        Set<UUID>
    ) async -> Bool

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
        prepareRuntimeRetirement: @escaping @MainActor (
            ProfileRetirementRecord
        ) async throws -> Void = { _ in },
        rehydrateRetirementState: @escaping @MainActor (
            ProfileRetirementRecord
        ) async throws -> Void = { _ in },
        sanitizeDeferredReferences: @escaping @MainActor (
            Set<UUID>
        ) async -> Bool = { _ in true },
        cleanupFactory: @escaping CleanupFactory
    ) {
        self.ledger = ledger
        self.migrateReferences = migrateReferences
        self.prepareRuntimeRetirement = prepareRuntimeRetirement
        self.rehydrateRetirementState = rehydrateRetirementState
        self.sanitizeDeferredReferences = sanitizeDeferredReferences
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

    func recover() async throws -> ProfileRetirementStartupRecoveryReport {
        var report = ProfileRetirementStartupRecoveryReport(
            issues: ledger.quarantinedRetirements.map { quarantine in
                ProfileRetirementRecoveryIssue(
                    profileID: quarantine.profileID,
                    phase: quarantine.phaseRawValue,
                    kind: .quarantinedRecord,
                    reason: quarantine.reason,
                    requiresReferenceSanitization: true
                )
            }
        )
        for initialRecord in ledger.records() {
            do {
                try await recover(initialRecord)
            } catch let error as ProfileRetirementStartupRecoveryError {
                report.issues.append(issue(for: initialRecord, error: error))
            }
        }
        let profileIDs = report.profileIDsRequiringReferenceSanitization
        if profileIDs.isEmpty == false,
           await sanitizeDeferredReferences(profileIDs) == false {
            for profileID in profileIDs {
                report.issues.append(
                    ProfileRetirementRecoveryIssue(
                        profileID: profileID,
                        phase: "sanitizingReferences",
                        kind: .referenceMigration,
                        reason: "Blocked profile references will be sanitized again during restore.",
                        requiresReferenceSanitization: true
                    )
                )
            }
        }
        if report.hasDeferredRecovery {
            ledger.allowUnrelatedReferencesDuringDeferredRecovery()
        }
        return report
    }

    func rehydrateCompletedRetirements(
        _ records: [ProfileRetirementRecord]
    ) async -> ProfileRetirementStartupRecoveryReport {
        var report = ProfileRetirementStartupRecoveryReport()
        for record in records where record.isCompletedTombstone {
            do {
                try await rehydrateRuntimeState(record)
            } catch let error as ProfileRetirementStartupRecoveryError {
                report.issues.append(issue(for: record, error: error))
            } catch {
                report.issues.append(
                    issue(
                        for: record,
                        error: .cleanupDeferred(
                            profileID: record.snapshot.id,
                            reason: error.localizedDescription
                        )
                    )
                )
            }
        }
        return report
    }

    private func recover(_ initialRecord: ProfileRetirementRecord) async throws {
        switch initialRecord.phase {
        case .reserved:
            guard try ledger.cancel(initialRecord.token) else {
                throw ProfileRetirementStartupRecoveryError.staleRecord(
                    profileID: initialRecord.snapshot.id,
                    operation: "cancel its pre-cleanup reservation"
                )
            }
        case .migratingReferences:
            try await migrateReferencesForRecovery(initialRecord)
            try await prepareRuntimeForRetirement(initialRecord)
            guard try ledger.commitLogicalDeletion(initialRecord.token) else {
                throw ProfileRetirementStartupRecoveryError.staleRecord(
                    profileID: initialRecord.snapshot.id,
                    operation: "commit recovered logical deletion"
                )
            }
            guard try ledger.beginCleaning(initialRecord.token),
                  let cleaningRecord = ledger.record(for: initialRecord.token)
            else {
                throw ProfileRetirementStartupRecoveryError.staleRecord(
                    profileID: initialRecord.snapshot.id,
                    operation: "begin recovered cleanup"
                )
            }
            try await resumeCleanup(cleaningRecord)
        case .logicallyDeleted:
            try await prepareRuntimeForRetirement(initialRecord)
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
            try await rehydrateRuntimeState(initialRecord)
            try await resumeCleanup(initialRecord)
        case .retired:
            guard initialRecord.nextCleanupStep == .completed else {
                throw ProfileRetirementStartupRecoveryError.invalidPersistedPhase(
                    profileID: initialRecord.snapshot.id
                )
            }
            try await rehydrateRuntimeState(initialRecord)
        }
    }

    private func migrateReferencesForRecovery(
        _ record: ProfileRetirementRecord
    ) async throws {
        do {
            try await migrateReferences(record)
        } catch let error as ProfileRetirementStartupRecoveryError {
            throw error
        } catch {
            throw ProfileRetirementStartupRecoveryError.referenceMigrationFailed(
                profileID: record.snapshot.id
            )
        }
    }

    private func prepareRuntimeForRetirement(
        _ record: ProfileRetirementRecord
    ) async throws {
        do {
            try await prepareRuntimeRetirement(record)
        } catch let error as ProfileRetirementStartupRecoveryError {
            throw error
        } catch {
            throw ProfileRetirementStartupRecoveryError.cleanupDeferred(
                profileID: record.snapshot.id,
                reason: error.localizedDescription
            )
        }
    }

    private func rehydrateRuntimeState(
        _ record: ProfileRetirementRecord
    ) async throws {
        do {
            try await rehydrateRetirementState(record)
        } catch let error as ProfileRetirementStartupRecoveryError {
            throw error
        } catch {
            throw ProfileRetirementStartupRecoveryError.cleanupDeferred(
                profileID: record.snapshot.id,
                reason: error.localizedDescription
            )
        }
    }

    private func issue(
        for record: ProfileRetirementRecord,
        error: ProfileRetirementStartupRecoveryError
    ) -> ProfileRetirementRecoveryIssue {
        let kind: ProfileRetirementRecoveryIssue.Kind
        let requiresSanitization: Bool
        switch error {
        case .referenceMigrationUnavailable, .referenceMigrationFailed:
            kind = .referenceMigration
            requiresSanitization = true
        case .staleRecord(_, let operation)
        where operation.contains("logical deletion"):
            kind = .logicalDeletion
            requiresSanitization = record.phase == .migratingReferences
        case .cleanupPreparationFailed, .cleanupDeferred,
             .invalidPersistedPhase, .staleRecord:
            kind = .cleanup
            requiresSanitization = record.phase == .reserved
        }
        return ProfileRetirementRecoveryIssue(
            profileID: record.snapshot.id,
            phase: record.phase.rawValue,
            kind: kind,
            reason: error.localizedDescription,
            requiresReferenceSanitization: requiresSanitization
        )
    }

    private func resumeCleanup(_ record: ProfileRetirementRecord) async throws {
        let token = record.token
        let cleanup = cleanupFactory(record.snapshot)
        do {
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
        } catch let error as ProfileRetirementStartupRecoveryError {
            throw error
        } catch {
            throw ProfileRetirementStartupRecoveryError.cleanupDeferred(
                profileID: record.snapshot.id,
                reason: error.localizedDescription
            )
        }
        guard try ledger.markRetired(token) else {
            throw ProfileRetirementStartupRecoveryError.staleRecord(
                profileID: record.snapshot.id,
                operation: "finish cleanup"
            )
        }
    }
}
