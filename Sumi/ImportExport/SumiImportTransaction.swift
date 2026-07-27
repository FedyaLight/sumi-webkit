import Foundation

@MainActor
final class SumiImportTransaction {
    private let materializer: any SumiImportRuntimeMaterializing
    private let runtime: any SumiImportRuntimeMutating
    private let bookmarks: any SumiImportBookmarkMutating
    private let backupWriter: any SumiImportBackupWriting
    private let journal: any SumiImportTransactionJournal
    private let profileRetirement: any SumiImportProfileRetiring
    private let executionGate: SumiImportTransactionExecutionGate
    private let shouldInterrupt: (SumiImportTransactionFaultPoint) -> Bool

    init(
        materializer: any SumiImportRuntimeMaterializing,
        runtime: any SumiImportRuntimeMutating,
        bookmarks: any SumiImportBookmarkMutating,
        backupWriter: any SumiImportBackupWriting,
        journal: any SumiImportTransactionJournal,
        profileRetirement: any SumiImportProfileRetiring = SumiImportNoopProfileRetirement(),
        executionGate: SumiImportTransactionExecutionGate = .shared,
        shouldInterrupt: @escaping (SumiImportTransactionFaultPoint) -> Bool = { _ in false }
    ) {
        self.materializer = materializer
        self.runtime = runtime
        self.bookmarks = bookmarks
        self.backupWriter = backupWriter
        self.journal = journal
        self.profileRetirement = profileRetirement
        self.executionGate = executionGate
        self.shouldInterrupt = shouldInterrupt
    }

    func commit(_ plan: SumiImportPlan) async throws -> SumiImportReport {
        await executionGate.acquire()
        defer { executionGate.release() }
        try Task.checkCancellation()
        return try await commitExclusively(plan)
    }

    func recoverIfNeeded() async throws -> SumiImportRecoveryReport? {
        await executionGate.acquire()
        defer { executionGate.release() }
        try Task.checkCancellation()
        return try await recoverIfNeededExclusively()
    }

    private func commitExclusively(_ plan: SumiImportPlan) async throws -> SumiImportReport {
        _ = try await recoverIfNeededExclusively()

        guard plan.hasMutations else {
            return SumiImportReport(
                warnings: plan.warnings,
                preRestoreBackupURL: nil,
                appliedCategories: [],
                bookmarkSummary: nil
            )
        }

        let runtimeCheckpoint = plan.changesRuntime ? runtime.checkpoint() : nil
        let importedState: SumiImportRuntimeState?
        do {
            importedState = try runtimeCheckpoint.map {
                try materializer.materialize(plan, preserving: $0)
            }
        } catch {
            throw commitFailure(error, rollbackErrors: [], backupURL: nil)
        }

        let bookmarkCheckpoint = plan.bookmarkMutation.changesBookmarks
            ? bookmarks.checkpoint()
            : nil
        let preRestoreBackupURL: URL?
        do {
            preRestoreBackupURL = plan.mode == .replace
                ? try backupWriter.writeAutomaticPreRestoreBackup(data: plan.baseline)
                : nil
        } catch {
            throw commitFailure(error, rollbackErrors: [], backupURL: nil)
        }

        var runtimeMutationSession: SumiImportRuntimeMutationSession?
        do {
            runtimeMutationSession = try importedState.map { importedState in
                try runtime.beginMutation(
                    covering: [importedState] + (runtimeCheckpoint.map { [$0] } ?? [])
                )
            }
        } catch {
            throw commitFailure(
                error,
                rollbackErrors: [],
                backupURL: preRestoreBackupURL
            )
        }
        defer {
            if let runtimeMutationSession {
                precondition(
                    runtime.endMutation(runtimeMutationSession),
                    "Import transaction lost its exact runtime mutation session"
                )
            }
        }

        var record = SumiImportTransactionJournalRecord(
            phase: .prepared,
            baseline: plan.baseline,
            targetRuntimeData: plan.targetRuntimeData,
            runtimeCheckpoint: runtimeCheckpoint.map(SumiImportDurableRuntimeCheckpoint.init),
            bookmarkCheckpoint: bookmarkCheckpoint.map(SumiImportBookmarkCheckpoint.init),
            preRestoreBackupURL: preRestoreBackupURL,
            profileTransition: plan.profileTransition
        )

        do {
            try await persistPrepared(record)
        } catch is SumiImportTransactionInterruption {
            throw SumiImportTransactionInterruption()
        } catch {
            throw commitFailure(error, rollbackErrors: [], backupURL: preRestoreBackupURL)
        }

        let bookmarkSummary: SumiBookmarksImportSummary?
        do {
            if let importedState, let runtimeMutationSession {
                try await runtime.install(
                    importedState,
                    in: runtimeMutationSession
                )
                try interruptIfRequested(at: .runtimeInstalled)
            }
            record = try await transition(record, to: .runtimeCommitted)

            bookmarkSummary = bookmarkCheckpoint != nil
                ? try bookmarks.commit(plan.bookmarkMutation)
                : nil
            if bookmarkCheckpoint != nil {
                try interruptIfRequested(at: .bookmarksMutated)
            }
            record = try await transition(record, to: .bookmarksCommitted)
        } catch is SumiImportTransactionInterruption {
            throw SumiImportTransactionInterruption()
        } catch let importError {
            let compensation = try await compensate(
                record: record,
                runtimeCheckpoint: runtimeCheckpoint,
                bookmarkCheckpoint: bookmarkCheckpoint,
                runtimeMutationSession: runtimeMutationSession
            )
            endRuntimeMutationSession(&runtimeMutationSession)
            let rollbackErrors = await finishCommitCompensation(
                compensation,
                transition: plan.profileTransition,
                baseline: plan.baseline
            )
            throw commitFailure(
                importError,
                rollbackErrors: rollbackErrors,
                backupURL: preRestoreBackupURL
            )
        }

        endRuntimeMutationSession(&runtimeMutationSession)
        try await finalizeCommittedImport(
            record: record,
            transition: plan.profileTransition,
            backupURL: preRestoreBackupURL
        )

        return SumiImportReport(
            warnings: reportWarnings(plan.warnings, bookmarkSummary: bookmarkSummary),
            preRestoreBackupURL: preRestoreBackupURL,
            appliedCategories: plan.categories,
            bookmarkSummary: bookmarkSummary
        )
    }

    private func recoverIfNeededExclusively() async throws -> SumiImportRecoveryReport? {
        guard var record = try await journal.load() else { return nil }
        let report = SumiImportRecoveryReport(
            preRestoreBackupURL: record.preRestoreBackupURL
        )

        if try await finalizeRecoveryIfPossible(record) {
            return report
        }

        var recoveryErrors: [Error] = []
        if record.phase != .compensating {
            do {
                record = try await transition(record, to: .compensating)
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                recoveryErrors.append(error)
            }
        }

        var runtimeRecovery: (
            checkpoint: SumiImportRuntimeState,
            session: SumiImportRuntimeMutationSession
        )?
        if let durableCheckpoint = record.runtimeCheckpoint {
            do {
                let currentState = runtime.checkpoint()
                let rollbackPlan = SumiImportPlan(
                    baseline: record.targetRuntimeData,
                    targetRuntimeData: record.baseline,
                    bookmarkMutation: .none,
                    categories: [],
                    mode: .replace,
                    warnings: []
                )
                let materializedState = try materializer.materialize(
                    rollbackPlan,
                    preserving: currentState
                )
                let checkpoint = durableCheckpoint.applying(to: materializedState)
                let session = try runtime.beginMutation(
                    covering: [currentState, checkpoint]
                )
                runtimeRecovery = (checkpoint, session)
            } catch {
                recoveryErrors.append(error)
            }
        }
        defer {
            if let runtimeRecovery {
                precondition(
                    runtime.endMutation(runtimeRecovery.session),
                    "Import recovery lost its exact runtime mutation session"
                )
            }
        }

        if let bookmarkCheckpoint = record.bookmarkCheckpoint {
            do {
                try bookmarks.restore(bookmarkCheckpoint.makeSnapshot())
                try interruptIfRequested(at: .bookmarksCompensated)
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                recoveryErrors.append(error)
            }
        }

        if let runtimeRecovery {
            do {
                try await runtime.restore(
                    runtimeRecovery.checkpoint,
                    in: runtimeRecovery.session
                )
                try interruptIfRequested(at: .runtimeCompensated)
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                recoveryErrors.append(error)
            }
        }

        if recoveryErrors.isEmpty,
           !record.profileTransition.createdProfileIDs.isEmpty {
            do {
                record = try await transition(
                    record,
                    to: .compensatingProfiles
                )
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                recoveryErrors.append(error)
            }
        }

        if let active = runtimeRecovery {
            precondition(
                runtime.endMutation(active.session),
                "Import recovery lost its exact runtime mutation session"
            )
            runtimeRecovery = nil
        }

        if recoveryErrors.isEmpty,
           record.phase == .compensatingProfiles {
            do {
                try await retireCompensatedProfiles(
                    record.profileTransition.createdProfileIDs,
                    baseline: record.baseline
                )
            } catch {
                recoveryErrors.append(error)
            }
        }

        if recoveryErrors.isEmpty {
            do {
                record = try await transition(record, to: .completed)
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                recoveryErrors.append(error)
            }
        }

        if recoveryErrors.isEmpty {
            do {
                try await journal.clear()
                return report
            } catch {
                recoveryErrors.append(error)
            }
        }

        throw SumiImportTransactionError.recoveryFailed(
            rollbackErrors: recoveryErrors,
            preRestoreBackupURL: record.preRestoreBackupURL
        )
    }

    private func compensate(
        record: SumiImportTransactionJournalRecord,
        runtimeCheckpoint: SumiImportRuntimeState?,
        bookmarkCheckpoint: SumiBookmarksSnapshot?,
        runtimeMutationSession: SumiImportRuntimeMutationSession?
    ) async throws -> (
        record: SumiImportTransactionJournalRecord,
        errors: [Error]
    ) {
        var record = record
        var rollbackErrors: [Error] = []
        do {
            record = try await transition(record, to: .compensating)
        } catch is SumiImportTransactionInterruption {
            throw SumiImportTransactionInterruption()
        } catch {
            rollbackErrors.append(error)
        }

        if let bookmarkCheckpoint {
            do {
                try bookmarks.restore(bookmarkCheckpoint)
                try interruptIfRequested(at: .bookmarksCompensated)
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                rollbackErrors.append(error)
            }
        }

        if let runtimeCheckpoint, let runtimeMutationSession {
            do {
                try await runtime.restore(
                    runtimeCheckpoint,
                    in: runtimeMutationSession
                )
                try interruptIfRequested(at: .runtimeCompensated)
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                rollbackErrors.append(error)
            }
        }

        if rollbackErrors.isEmpty {
            do {
                if record.profileTransition.createdProfileIDs.isEmpty {
                    record = try await transition(record, to: .completed)
                    try await journal.clear()
                } else {
                    record = try await transition(
                        record,
                        to: .compensatingProfiles
                    )
                }
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                rollbackErrors.append(error)
            }
        }
        return (record, rollbackErrors)
    }

    private func transition(
        _ record: SumiImportTransactionJournalRecord,
        to phase: SumiImportTransactionPhase
    ) async throws -> SumiImportTransactionJournalRecord {
        guard record.phase.canTransition(to: phase) else {
            throw SumiImportTransactionJournalError.invalidTransition(
                from: record.phase,
                to: phase
            )
        }
        var updatedRecord = record
        updatedRecord.phase = phase
        try await journal.save(updatedRecord)
        try interruptIfRequested(at: .phasePersisted(phase))
        return updatedRecord
    }

    private func persistPrepared(_ record: SumiImportTransactionJournalRecord) async throws {
        precondition(record.phase == .prepared)
        try await journal.save(record)
        try interruptIfRequested(at: .phasePersisted(.prepared))
    }

    private func interruptIfRequested(
        at faultPoint: SumiImportTransactionFaultPoint
    ) throws {
        if shouldInterrupt(faultPoint) {
            throw SumiImportTransactionInterruption()
        }
    }

    private func commitFailure(
        _ error: Error,
        rollbackErrors: [Error],
        backupURL: URL?
    ) -> SumiImportTransactionError {
        .commitFailed(
            importError: error,
            rollbackErrors: rollbackErrors,
            preRestoreBackupURL: backupURL
        )
    }

    private func reportWarnings(
        _ planningWarnings: [String],
        bookmarkSummary: SumiBookmarksImportSummary?
    ) -> [String] {
        guard let bookmarkSummary else { return planningWarnings }
        var warnings = planningWarnings
        if bookmarkSummary.duplicates > 0 {
            warnings.append("Skipped \(bookmarkSummary.duplicates) duplicate bookmarks.")
        }
        if bookmarkSummary.failed > 0 {
            warnings.append("Skipped \(bookmarkSummary.failed) invalid bookmarks.")
        }
        return warnings
    }
}

private extension SumiImportTransaction {
    func finishCommitCompensation(
        _ compensation: (
            record: SumiImportTransactionJournalRecord,
            errors: [Error]
        ),
        transition: SumiImportProfileTransition,
        baseline: SumiPortableData
    ) async -> [Error] {
        var record = compensation.record
        var rollbackErrors = compensation.errors
        guard rollbackErrors.isEmpty,
              !transition.createdProfileIDs.isEmpty
        else { return rollbackErrors }

        do {
            try await retireCompensatedProfiles(
                transition.createdProfileIDs,
                baseline: baseline
            )
            record = try await self.transition(record, to: .completed)
            try await journal.clear()
        } catch {
            rollbackErrors.append(error)
        }
        return rollbackErrors
    }

    func finalizeCommittedImport(
        record: SumiImportTransactionJournalRecord,
        transition profileTransition: SumiImportProfileTransition,
        backupURL: URL?
    ) async throws {
        var record = record
        if !profileTransition.retiringProfileIDs.isEmpty {
            do {
                record = try await transition(record, to: .retiringProfiles)
            } catch {
                throw SumiImportTransactionError.commitFinalizationFailed(
                    finalizationError: error,
                    preRestoreBackupURL: backupURL
                )
            }
            do {
                try await retireImportedProfiles(profileTransition)
            } catch {
                throw SumiImportTransactionError.profileRetirementPending(
                    retirementError: error,
                    preRestoreBackupURL: backupURL
                )
            }
        }

        do {
            _ = try await transition(record, to: .completed)
        } catch is SumiImportTransactionInterruption {
            throw SumiImportTransactionInterruption()
        } catch {
            throw SumiImportTransactionError.commitFinalizationFailed(
                finalizationError: error,
                preRestoreBackupURL: backupURL
            )
        }

        do {
            try await journal.clear()
        } catch {
            throw SumiImportTransactionError.commitFinalizationFailed(
                finalizationError: error,
                preRestoreBackupURL: backupURL
            )
        }
    }

    func finalizeRecoveryIfPossible(
        _ record: SumiImportTransactionJournalRecord
    ) async throws -> Bool {
        var record = record
        switch record.phase {
        case .completed:
            do {
                try await journal.clear()
                return true
            } catch {
                throw SumiImportTransactionError.recoveryFailed(
                    rollbackErrors: [error],
                    preRestoreBackupURL: record.preRestoreBackupURL
                )
            }
        case .retiringProfiles:
            do {
                try await retireImportedProfiles(record.profileTransition)
                record = try await transition(record, to: .completed)
                try await journal.clear()
                return true
            } catch {
                throw SumiImportTransactionError.profileRetirementPending(
                    retirementError: error,
                    preRestoreBackupURL: record.preRestoreBackupURL
                )
            }
        case .compensatingProfiles:
            do {
                try await retireCompensatedProfiles(
                    record.profileTransition.createdProfileIDs,
                    baseline: record.baseline
                )
                record = try await transition(record, to: .completed)
                try await journal.clear()
                return true
            } catch {
                throw SumiImportTransactionError.recoveryFailed(
                    rollbackErrors: [error],
                    preRestoreBackupURL: record.preRestoreBackupURL
                )
            }
        default:
            return false
        }
    }

    func endRuntimeMutationSession(
        _ session: inout SumiImportRuntimeMutationSession?
    ) {
        guard let active = session else { return }
        precondition(
            runtime.endMutation(active),
            "Import transaction lost its exact runtime mutation session"
        )
        session = nil
    }

    func retireImportedProfiles(
        _ transition: SumiImportProfileTransition
    ) async throws {
        guard let fallbackProfileID = transition.fallbackProfileID else {
            throw SumiImportProfileRetirementError.unavailable
        }
        try await profileRetirement.retireProfiles(
            transition.retiringProfileIDs,
            fallbackProfileID: fallbackProfileID
        )
    }

    func retireCompensatedProfiles(
        _ profileIDs: Set<UUID>,
        baseline: SumiPortableData
    ) async throws {
        guard let fallbackProfileID = baseline.profiles.first.flatMap({
            UUID(uuidString: $0.id)
        }) else {
            throw SumiImportProfileRetirementError.unavailable
        }
        try await profileRetirement.retireProfiles(
            profileIDs,
            fallbackProfileID: fallbackProfileID
        )
    }
}

private struct SumiImportTransactionInterruption: Error {}

enum SumiImportTransactionFaultPoint: Equatable, Sendable {
    case phasePersisted(SumiImportTransactionPhase)
    case runtimeInstalled
    case bookmarksMutated
    case bookmarksCompensated
    case runtimeCompensated
}

@MainActor
final class SumiImportTransactionExecutionGate {
    static let shared = SumiImportTransactionExecutionGate()

    private var isAcquired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isAcquired else {
            isAcquired = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard waiters.isEmpty else {
            waiters.removeFirst().resume()
            return
        }
        isAcquired = false
    }
}
