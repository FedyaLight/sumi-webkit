import Foundation

enum ProfileDeletionMigrationOutcome: Equatable {
    case committed
    case rejected
    case timedOut
    case alreadyRunning
}

enum ProfileDeletionOperationID: Hashable {
    case space(UUID)
    case tab(UUID)
}

struct ProfileDeletionOperation {
    let id: ProfileDeletionOperationID
    let start: @MainActor (
        @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome
    let cancelPending: @MainActor () -> Void
}

struct ProfileDeletionSettlementPlan {
    let deletedProfileID: UUID
    let fallbackProfileID: UUID
    let operations: [ProfileDeletionOperation]
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
            ProfileDeletionOperationID: ProfileDeletionOperation
        ]
        let continuation: CheckedContinuation<
            ProfileDeletionMigrationOutcome,
            Never
        >
        var pending: Set<ProfileDeletionOperationID>
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

    private let abortTransitions: (Set<UUID>) -> Int
    private let waitForTimeout: @MainActor () async -> Void
    private var activeRun: Run?

    init(
        timeout: Duration = .seconds(30),
        waitForTimeout: (@MainActor () async -> Void)? = nil,
        abortTransitions: @escaping (Set<UUID>) -> Int
    ) {
        self.abortTransitions = abortTransitions
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
        operationID: ProfileDeletionOperationID,
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
        _ = abortTransitions(
            [run.plan.deletedProfileID, run.plan.fallbackProfileID]
        )
        for operationID in run.pending.sorted(by: operationOrder) {
            run.operationsByID[operationID]?.cancelPending()
        }
        run.continuation.resume(returning: .timedOut)
    }

    private func operationOrder(
        _ lhs: ProfileDeletionOperationID,
        _ rhs: ProfileDeletionOperationID
    ) -> Bool {
        operationSortKey(lhs) < operationSortKey(rhs)
    }

    private func operationSortKey(
        _ operation: ProfileDeletionOperationID
    ) -> String {
        switch operation {
        case .space(let id):
            return "0-\(id.uuidString)"
        case .tab(let id):
            return "1-\(id.uuidString)"
        }
    }
}
