import Foundation

@MainActor
final class SumiImportTransaction {
    private let materializer: any SumiImportRuntimeMaterializing
    private let runtime: any SumiImportRuntimeMutating
    private let bookmarks: any SumiImportBookmarkMutating
    private let backupWriter: any SumiImportBackupWriting
    private let journal: any SumiImportTransactionJournal
    private let executionGate: SumiImportTransactionExecutionGate
    private let shouldInterrupt: (SumiImportTransactionFaultPoint) -> Bool

    init(
        materializer: any SumiImportRuntimeMaterializing,
        runtime: any SumiImportRuntimeMutating,
        bookmarks: any SumiImportBookmarkMutating,
        backupWriter: any SumiImportBackupWriting,
        journal: any SumiImportTransactionJournal = SumiImportTransactionFileJournal(),
        executionGate: SumiImportTransactionExecutionGate = .shared,
        shouldInterrupt: @escaping (SumiImportTransactionFaultPoint) -> Bool = { _ in false }
    ) {
        self.materializer = materializer
        self.runtime = runtime
        self.bookmarks = bookmarks
        self.backupWriter = backupWriter
        self.journal = journal
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

        var record = SumiImportTransactionJournalRecord(
            phase: .prepared,
            baseline: plan.baseline,
            targetRuntimeData: plan.targetRuntimeData,
            runtimeCheckpoint: runtimeCheckpoint.map(SumiImportDurableRuntimeCheckpoint.init),
            bookmarkCheckpoint: bookmarkCheckpoint.map(SumiImportBookmarkCheckpoint.init),
            preRestoreBackupURL: preRestoreBackupURL
        )

        do {
            try persistPrepared(record)
        } catch is SumiImportTransactionInterruption {
            throw SumiImportTransactionInterruption()
        } catch {
            throw commitFailure(error, rollbackErrors: [], backupURL: preRestoreBackupURL)
        }

        do {
            if let importedState {
                try await runtime.install(importedState)
                try interruptIfRequested(at: .runtimeInstalled)
            }
            try transition(&record, to: .runtimeCommitted)

            let bookmarkSummary = bookmarkCheckpoint != nil
                ? try bookmarks.commit(plan.bookmarkMutation)
                : nil
            if bookmarkCheckpoint != nil {
                try interruptIfRequested(at: .bookmarksMutated)
            }
            try transition(&record, to: .bookmarksCommitted)
            try transition(&record, to: .completed)
            try? journal.clear()

            return SumiImportReport(
                warnings: reportWarnings(plan.warnings, bookmarkSummary: bookmarkSummary),
                preRestoreBackupURL: preRestoreBackupURL,
                appliedCategories: plan.categories,
                bookmarkSummary: bookmarkSummary
            )
        } catch is SumiImportTransactionInterruption {
            throw SumiImportTransactionInterruption()
        } catch let importError {
            let rollbackErrors = try await compensate(
                record: &record,
                runtimeCheckpoint: runtimeCheckpoint,
                bookmarkCheckpoint: bookmarkCheckpoint
            )
            throw commitFailure(
                importError,
                rollbackErrors: rollbackErrors,
                backupURL: preRestoreBackupURL
            )
        }
    }

    private func recoverIfNeededExclusively() async throws -> SumiImportRecoveryReport? {
        guard var record = try journal.load() else { return nil }
        let report = SumiImportRecoveryReport(
            preRestoreBackupURL: record.preRestoreBackupURL
        )

        if record.phase == .completed {
            do {
                try journal.clear()
                return report
            } catch {
                throw SumiImportTransactionError.recoveryFailed(
                    rollbackErrors: [error],
                    preRestoreBackupURL: record.preRestoreBackupURL
                )
            }
        }

        var recoveryErrors: [Error] = []
        if record.phase != .compensating {
            do {
                try transition(&record, to: .compensating)
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                recoveryErrors.append(error)
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
                try await runtime.restore(durableCheckpoint.applying(to: materializedState))
                try interruptIfRequested(at: .runtimeCompensated)
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                recoveryErrors.append(error)
            }
        }

        if recoveryErrors.isEmpty {
            do {
                try transition(&record, to: .completed)
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                recoveryErrors.append(error)
            }
        }

        if recoveryErrors.isEmpty {
            do {
                try journal.clear()
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
        record: inout SumiImportTransactionJournalRecord,
        runtimeCheckpoint: SumiImportRuntimeState?,
        bookmarkCheckpoint: SumiBookmarksSnapshot?
    ) async throws -> [Error] {
        var rollbackErrors: [Error] = []
        do {
            try transition(&record, to: .compensating)
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

        if let runtimeCheckpoint {
            do {
                try await runtime.restore(runtimeCheckpoint)
                try interruptIfRequested(at: .runtimeCompensated)
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                rollbackErrors.append(error)
            }
        }

        if rollbackErrors.isEmpty {
            do {
                try transition(&record, to: .completed)
            } catch is SumiImportTransactionInterruption {
                throw SumiImportTransactionInterruption()
            } catch {
                rollbackErrors.append(error)
            }
        }

        if rollbackErrors.isEmpty {
            try? journal.clear()
        }
        return rollbackErrors
    }

    private func transition(
        _ record: inout SumiImportTransactionJournalRecord,
        to phase: SumiImportTransactionPhase
    ) throws {
        guard record.phase.canTransition(to: phase) else {
            throw SumiImportTransactionJournalError.invalidTransition(
                from: record.phase,
                to: phase
            )
        }
        var updatedRecord = record
        updatedRecord.phase = phase
        try journal.save(updatedRecord)
        record = updatedRecord
        try interruptIfRequested(at: .phasePersisted(phase))
    }

    private func persistPrepared(_ record: SumiImportTransactionJournalRecord) throws {
        precondition(record.phase == .prepared)
        try journal.save(record)
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
