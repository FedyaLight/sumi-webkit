import Foundation

enum TabStoreRestoreOutcome {
    case abandoned
    case settledWithoutInstall
    case installed

    var shouldFinish: Bool { self != .abandoned }
    var didInstall: Bool { self == .installed }
}

@MainActor
final class TabStoreRestoreAttemptExecutor {
    private let payloadLoader: any TabRestorePayloadLoading
    private let structuralStore: TabStructuralSnapshotStore
    private let structuralLookup: TabStructuralLookupCoordinator
    private let loadLifecycle: TabStartupRestoreLifecycle
    private let payloadApplier: TabRestorePayloadApplyService

    init(
        payloadLoader: any TabRestorePayloadLoading,
        structuralStore: TabStructuralSnapshotStore,
        structuralLookup: TabStructuralLookupCoordinator,
        loadLifecycle: TabStartupRestoreLifecycle,
        payloadApplier: TabRestorePayloadApplyService
    ) {
        self.payloadLoader = payloadLoader
        self.structuralStore = structuralStore
        self.structuralLookup = structuralLookup
        self.loadLifecycle = loadLifecycle
        self.payloadApplier = payloadApplier
    }

    func perform(
        _ attempt: TabStartupRestoreAttempt
    ) async -> TabStoreRestoreOutcome {
        let signpostState = PerformanceTrace.beginInterval("TabManager.loadFromStore")
        defer {
            PerformanceTrace.endInterval("TabManager.loadFromStore", signpostState)
        }

        guard loadIsCurrent(attempt) else { return .abandoned }
        let expectedRevision = attempt.expectedStructuralRevision
        guard structuralLookup.mutationRevision == expectedRevision else {
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
            guard structuralLookup.mutationRevision == expectedRevision else {
                logStaleRevision(expectedRevision, stage: "while loading")
                return .settledWithoutInstall
            }

            let disposition = payloadApplier.apply(
                payload,
                runtimeAttachment: attempt.runtimeAttachment,
                admitted: {
                    self.loadLifecycle.admitsInstall(attempt)
                        && self.structuralLookup.mutationRevision == expectedRevision
                },
                onInstalled: { _ in
                    _ = self.loadLifecycle.markStructuralCommit(attempt)
                }
            )
            switch disposition {
            case .notInstalled:
                return loadIsCurrent(attempt)
                    && structuralLookup.mutationRevision != expectedRevision
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

    private func loadIsCurrent(_ attempt: TabStartupRestoreAttempt) -> Bool {
        Task.isCancelled == false && loadLifecycle.admitsInstall(attempt)
    }

    private func logStaleRevision(_ expected: UInt64, stage: String) {
        RuntimeDiagnostics.debug(
            "Skipped stale startup restore \(stage) because the live tab structure changed (expected revision: \(expected), current revision: \(structuralLookup.mutationRevision)).",
            category: "TabManager"
        )
    }
}
