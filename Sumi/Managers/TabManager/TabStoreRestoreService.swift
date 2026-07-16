import Foundation

/// Restores persisted tab structure and settles one exact attachment-bound attempt.
@MainActor
final class TabStoreRestoreService {
    private enum Outcome {
        case abandoned
        case settledWithoutInstall
        case installed

        var shouldFinish: Bool { self != .abandoned }
        var didInstall: Bool { self == .installed }
    }

    private struct ActiveLoad {
        let attempt: TabStartupRestoreAttempt
        let task: Task<Void, Never>
    }

    private let payloadLoader: any TabRestorePayloadLoading
    private let structuralStore: TabStructuralSnapshotStore
    private let runtimeConnection: TabRuntimePortConnection
    private let structuralRevision: () -> UInt64
    private let loadLifecycle: TabStartupRestoreLifecycle
    private let payloadApplier: TabRestorePayloadApplyService
    private var activeLoad: ActiveLoad?

    var startupRestoreTask: Task<Void, Never>? { activeLoad?.task }

    init(
        payloadLoader: any TabRestorePayloadLoading,
        structuralStore: TabStructuralSnapshotStore,
        runtimeConnection: TabRuntimePortConnection,
        structuralRevision: @escaping () -> UInt64,
        loadLifecycle: TabStartupRestoreLifecycle,
        payloadApplier: TabRestorePayloadApplyService
    ) {
        self.payloadLoader = payloadLoader
        self.structuralStore = structuralStore
        self.runtimeConnection = runtimeConnection
        self.structuralRevision = structuralRevision
        self.loadLifecycle = loadLifecycle
        self.payloadApplier = payloadApplier
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
        let revision = expectedStructuralRevision ?? structuralRevision()
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
        let revision = expectedStructuralRevision ?? structuralRevision()
        guard let attempt = loadLifecycle.beginDirectLoad(
            using: runtimeAttachment,
            expectedStructuralRevision: revision
        ) else { return false }
        let outcome = await perform(attempt)
        return settleDirect(attempt, outcome: outcome)
    }

    private func schedule(_ attempt: TabStartupRestoreAttempt) {
        guard attempt.isRuntimeCurrent(), activeLoad == nil else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.perform(attempt)
            self.settleScheduled(
                attempt,
                outcome: outcome
            )
        }
        activeLoad = ActiveLoad(attempt: attempt, task: task)
    }

    private func perform(_ attempt: TabStartupRestoreAttempt) async -> Outcome {
        let signpostState = PerformanceTrace.beginInterval("TabManager.loadFromStore")
        defer {
            PerformanceTrace.endInterval("TabManager.loadFromStore", signpostState)
        }

        guard loadIsCurrent(attempt) else { return .abandoned }
        let expectedRevision = attempt.expectedStructuralRevision
        guard structuralRevision() == expectedRevision else {
            logStaleRevision(expectedRevision, stage: "before loading")
            return .settledWithoutInstall
        }

        do {
            let defaultProfileID = attempt.runtimeAttachment.lease.defaultProfileID
            if defaultProfileID == nil {
                RuntimeDiagnostics.debug(
                    "No profiles available to assign to spaces during load; reconciliation deferred.",
                    category: "TabManager"
                )
            }
            let payload = try await payloadLoader.load(
                defaultProfileId: defaultProfileID
            )
            guard loadIsCurrent(attempt) else { return .abandoned }
            guard structuralRevision() == expectedRevision else {
                logStaleRevision(expectedRevision, stage: "while loading")
                return .settledWithoutInstall
            }

            let disposition = payloadApplier.apply(
                payload,
                runtimeAttachment: attempt.runtimeAttachment,
                admitted: {
                    self.loadLifecycle.admitsInstall(attempt)
                        && self.structuralRevision() == expectedRevision
                },
                onInstalled: { _ in
                    _ = self.loadLifecycle.markStructuralCommit(attempt)
                }
            )
            switch disposition {
            case .notInstalled:
                return loadIsCurrent(attempt)
                    && structuralRevision() != expectedRevision
                    ? .settledWithoutInstall
                    : .abandoned
            case .installed(let installed):
                return await persistRepair(
                    installed.repair,
                    for: attempt
                ) ? .installed : .abandoned
            }
        } catch {
            guard loadIsCurrent(attempt) else { return .abandoned }
            RuntimeDiagnostics.debug(
                "SwiftData load error: \(String(describing: error))",
                category: "TabManager"
            )
            return .settledWithoutInstall
        }
    }

    private func persistRepair(
        _ repair: TabRestorePayloadApplyService.Repair?,
        for attempt: TabStartupRestoreAttempt
    ) async -> Bool {
        guard loadLifecycle.ownsCommitted(attempt) else { return false }
        guard let repair else { return true }
        RuntimeDiagnostics.debug(
            "Persisting restore repair: \(repair.reasons.joined(separator: ", "))",
            category: "TabManager"
        )
        _ = await structuralStore.persistFullReconcile(
            snapshot: repair.snapshot,
            generation: repair.generation
        )
        return loadLifecycle.ownsCommitted(attempt)
    }

    private func settleScheduled(
        _ attempt: TabStartupRestoreAttempt,
        outcome: Outcome
    ) {
        guard activeLoad?.attempt.matches(attempt) == true else { return }
        activeLoad = nil
        guard outcome.shouldFinish, loadLifecycle.finish(attempt) else { return }
    }

    private func settleDirect(
        _ attempt: TabStartupRestoreAttempt,
        outcome: Outcome
    ) -> Bool {
        guard outcome.shouldFinish,
              loadLifecycle.finish(attempt) else { return false }
        return outcome.didInstall
    }

    private func loadIsCurrent(_ attempt: TabStartupRestoreAttempt) -> Bool {
        Task.isCancelled == false && loadLifecycle.admitsInstall(attempt)
    }

    private func logStaleRevision(_ expected: UInt64, stage: String) {
        RuntimeDiagnostics.debug(
            "Skipped stale startup restore \(stage) because the live tab structure changed (expected revision: \(expected), current revision: \(structuralRevision())).",
            category: "TabManager"
        )
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
