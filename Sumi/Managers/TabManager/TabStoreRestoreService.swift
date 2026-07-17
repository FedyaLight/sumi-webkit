import Foundation

/// Restores persisted tab structure and settles one exact attachment-bound attempt.
@MainActor
final class TabStoreRestoreService {
    private struct ActiveLoad {
        let attempt: TabStartupRestoreAttempt
        let task: Task<Void, Never>
    }

    private let runtimeConnection: TabRuntimePortConnection
    private let structuralLookup: TabStructuralLookupCoordinator
    private let loadLifecycle: TabStartupRestoreLifecycle
    private let executor: TabStoreRestoreAttemptExecutor
    private var activeLoad: ActiveLoad?

    var startupRestoreTask: Task<Void, Never>? { activeLoad?.task }

    init(
        runtimeConnection: TabRuntimePortConnection,
        structuralLookup: TabStructuralLookupCoordinator,
        loadLifecycle: TabStartupRestoreLifecycle,
        executor: TabStoreRestoreAttemptExecutor
    ) {
        self.runtimeConnection = runtimeConnection
        self.structuralLookup = structuralLookup
        self.loadLifecycle = loadLifecycle
        self.executor = executor
    }

    deinit {
        MainActor.assumeIsolated {
            activeLoad?.task.cancel()
            activeLoad = nil
        }
    }

    func cancelPendingRestore(_ attempt: TabStartupRestoreAttempt) {
        guard let activeLoad,
              activeLoad.attempt.matches(attempt) else { return }
        activeLoad.task.cancel()
        self.activeLoad = nil
    }

    func loadFromStore(expectedStructuralRevision: UInt64? = nil) {
        guard let runtimeAttachment = captureRuntimeAttachment() else { return }
        let revision = expectedStructuralRevision ?? structuralLookup.mutationRevision
        guard let attempt = loadLifecycle.beginDirectLoad(
            using: runtimeAttachment,
            expectedStructuralRevision: revision
        ) else { return }
        schedule(attempt)
    }

    func loadFromStore(_ attempt: TabStartupRestoreAttempt) {
        schedule(attempt)
    }

    @discardableResult
    func loadFromStoreAwaitingResult(
        expectedStructuralRevision: UInt64? = nil
    ) async -> Bool {
        guard let runtimeAttachment = captureRuntimeAttachment() else {
            return false
        }
        let revision = expectedStructuralRevision ?? structuralLookup.mutationRevision
        guard let attempt = loadLifecycle.beginDirectLoad(
            using: runtimeAttachment,
            expectedStructuralRevision: revision
        ) else { return false }
        let outcome = await executor.perform(attempt)
        return settleDirect(attempt, outcome: outcome)
    }

    private func schedule(_ attempt: TabStartupRestoreAttempt) {
        guard attempt.isRuntimeCurrent(), activeLoad == nil else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.executor.perform(attempt)
            self.settleScheduled(attempt, outcome: outcome)
        }
        activeLoad = ActiveLoad(attempt: attempt, task: task)
    }

    private func settleScheduled(
        _ attempt: TabStartupRestoreAttempt,
        outcome: TabStoreRestoreOutcome
    ) {
        guard activeLoad?.attempt.matches(attempt) == true else { return }
        activeLoad = nil
        guard outcome.shouldFinish else { return }
        _ = loadLifecycle.finish(attempt)
    }

    private func settleDirect(
        _ attempt: TabStartupRestoreAttempt,
        outcome: TabStoreRestoreOutcome
    ) -> Bool {
        guard outcome.shouldFinish,
              loadLifecycle.finish(attempt) else { return false }
        return outcome.didInstall
    }

    private func captureRuntimeAttachment() -> TabRuntimeAttachmentWitness? {
        let lease = runtimeConnection.captureLease()
        guard runtimeConnection.accepts(lease) else { return nil }
        return TabRuntimeAttachmentWitness(
            connection: runtimeConnection,
            lease: lease
        )
    }
}
