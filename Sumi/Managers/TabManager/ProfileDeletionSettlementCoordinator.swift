import Foundation

enum ProfileDeletionMigrationOutcome: Equatable {
    case committed
    case rejected
    case timedOut
    case alreadyRunning
}

struct ProfileDeletionOperation {
    let id: UUID
    let start: @MainActor (
        @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome
    let cancelPending: @MainActor () -> Void
}

struct ProfileDeletionSettlementPlan {
    let deletedProfileID: UUID
    let fallbackProfileID: UUID
    let operations: [ProfileDeletionOperation]
    let abortTransitions: @MainActor (Set<UUID>) -> Int
}

/// Generic all-operation settlement gate. It knows nothing about TabManager,
/// shortcuts, profile resolution, or persistence.
@MainActor
final class ProfileDeletionSettlementCoordinator {
    @MainActor
    private final class Run {
        let id = UUID()
        let plan: ProfileDeletionSettlementPlan
        let operationsByID: [
            UUID: ProfileDeletionOperation
        ]
        let continuation: CheckedContinuation<
            ProfileDeletionMigrationOutcome,
            Never
        >
        var pending: Set<UUID>
        var didReject = false
        var timeoutTask: Task<Void, Never>?

        init(
            plan: ProfileDeletionSettlementPlan,
            continuation: CheckedContinuation<
                ProfileDeletionMigrationOutcome,
                Never
            >
        ) {
            self.plan = plan
            self.continuation = continuation
            operationsByID = Dictionary(
                uniqueKeysWithValues: plan.operations.map { ($0.id, $0) }
            )
            pending = Set(operationsByID.keys)
        }
    }

    private let waitForTimeout: @MainActor () async -> Void
    private var activeRun: Run?

    init(
        timeout: Duration = .seconds(30),
        waitForTimeout: (@MainActor () async -> Void)? = nil
    ) {
        self.waitForTimeout = waitForTimeout ?? {
            do {
                try await Task.sleep(for: timeout)
            } catch is CancellationError {
                return
            } catch {
                assertionFailure(
                    "Unexpected profile migration timeout error: \(error)"
                )
            }
        }
    }

    func settle(
        _ plan: ProfileDeletionSettlementPlan
    ) async -> ProfileDeletionMigrationOutcome {
        guard activeRun == nil else { return .alreadyRunning }
        precondition(plan.deletedProfileID != plan.fallbackProfileID)
        precondition(
            Set(plan.operations.map(\.id)).count == plan.operations.count,
            "Profile deletion migration operations must be unique"
        )
        guard !plan.operations.isEmpty else { return .committed }

        return await withCheckedContinuation { continuation in
            let run = Run(plan: plan, continuation: continuation)
            activeRun = run
            run.timeoutTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await waitForTimeout()
                guard !Task.isCancelled else { return }
                timeOut(runID: run.id)
            }

            for operation in plan.operations {
                guard activeRun?.id == run.id else { break }
                let outcome = operation.start { [weak self] settlement in
                    self?.record(
                        settlement,
                        operationID: operation.id,
                        runID: run.id
                    )
                }
                if let settlement = outcome.immediateSettlement {
                    record(
                        settlement,
                        operationID: operation.id,
                        runID: run.id
                    )
                }
            }
        }
    }

    private func record(
        _ settlement: ProfileTransitionSettlement,
        operationID: UUID,
        runID: UUID
    ) {
        guard let run = activeRun,
              run.id == runID,
              run.pending.remove(operationID) != nil else { return }
        if settlement != .committed {
            run.didReject = true
        }
        guard run.pending.isEmpty else { return }
        finish(run, outcome: run.didReject ? .rejected : .committed)
    }

    private func finish(
        _ run: Run,
        outcome: ProfileDeletionMigrationOutcome
    ) {
        guard activeRun?.id == run.id else { return }
        activeRun = nil
        run.timeoutTask?.cancel()
        run.timeoutTask = nil
        run.continuation.resume(returning: outcome)
    }

    private func timeOut(runID: UUID) {
        guard let run = activeRun, run.id == runID else { return }
        activeRun = nil
        run.timeoutTask = nil
        _ = run.plan.abortTransitions(
            [run.plan.deletedProfileID, run.plan.fallbackProfileID]
        )
        for operationID in run.pending.sorted(by: {
            $0.uuidString < $1.uuidString
        }) {
            run.operationsByID[operationID]?.cancelPending()
        }
        run.continuation.resume(returning: .timedOut)
    }
}
