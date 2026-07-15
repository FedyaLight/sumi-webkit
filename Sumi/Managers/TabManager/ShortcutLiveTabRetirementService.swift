import Foundation

/// Commits planned shortcut retirement and performs physical runtime release
/// only after the outermost structural transaction publishes its final model.
@MainActor
final class ShortcutLiveTabRetirementService {
    private let registry: LiveShortcutTabRegistry
    private let transaction: ShortcutLiveTabRetirementTransaction
    private let structuralLookup: TabStructuralLookupCoordinator
    private let runtimeTeardown: TabRuntimeTeardownService

    init(
        registry: LiveShortcutTabRegistry,
        batchRetirement: LiveShortcutTabBatchRetirement,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeConnection: TabRuntimePortConnection,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        self.registry = registry
        transaction = ShortcutLiveTabRetirementTransaction(
            registry: registry,
            batchRetirement: batchRetirement,
            runtimeConnection: runtimeConnection,
            runtimeTeardown: runtimeTeardown
        )
        self.structuralLookup = structuralLookup
        self.runtimeTeardown = runtimeTeardown
    }

    /// Returns `nil` only when the identifier is not a live shortcut instance.
    /// A non-nil empty result means the shortcut was recognized but retirement
    /// could not acquire its runtime lease, so generic tab removal must not run.
    func retire(tabId: UUID) -> ShortcutLiveTabRetirementResult? {
        guard let entry = registry.entry(tabId: tabId) else { return nil }
        guard var prepared = prepare(
            pinId: entry.pinId,
            in: entry.windowId
        ) else { return ShortcutLiveTabRetirementResult() }
        prepared = PreparedShortcutLiveTabRetirement(
            tabs: prepared.tabs,
            runtime: prepared.runtime,
            runtimeTeardown: prepared.runtimeTeardown,
            committedRuntimeRetirement: prepared.committedRuntimeRetirement,
            terminallyDrainedTabIDs: prepared.terminallyDrainedTabIDs,
            windowCommitPolicy: .retirementService,
            result: prepared.result
        )
        finishAfterCurrentBatch(prepared)
        return prepared.result
    }

    func retire(
        pinId: UUID,
        in windowId: UUID
    ) -> ShortcutLiveTabRetirementResult {
        guard let prepared = prepare(
            pinId: pinId,
            in: windowId
        ) else { return ShortcutLiveTabRetirementResult() }
        finishAfterCurrentBatch(prepared)
        return prepared.result
    }

    private func prepare(
        pinId: UUID,
        in windowId: UUID
    ) -> PreparedShortcutLiveTabRetirement? {
        structuralLookup.withTransaction {
            prepareRetirement(pinId: pinId, in: windowId)
        }
    }

    func retireDeletedPin(_ pinId: UUID) -> ShortcutLiveTabRetirementResult {
        guard let prepared = structuralLookup.withTransaction({
            prepareDeletedPinRetirement(pinId)
        }) else { return ShortcutLiveTabRetirementResult() }
        finishAfterCurrentBatch(prepared)
        return prepared.result
    }

    func prepareRetirement(
        pinId: UUID,
        in windowId: UUID
    ) -> PreparedShortcutLiveTabRetirement? {
        transaction.prepareRetirement(pinId: pinId, in: windowId)
    }

    func prepareReversibleRetirement(
        pinId: UUID,
        in windowId: UUID
    ) -> ReversibleShortcutLiveTabRetirement? {
        transaction.prepareReversibleRetirement(
            pinId: pinId,
            in: windowId
        )
    }

    func prepareRetirements(
        pinIds: Set<UUID>,
        in windowId: UUID
    ) -> PreparedShortcutLiveTabRetirement? {
        transaction.prepareRetirements(pinIds: pinIds, in: windowId)
    }

    func prepareDeletedPinRetirement(
        _ pinId: UUID
    ) -> PreparedShortcutLiveTabRetirement? {
        transaction.prepareDeletedPinRetirements([pinId])
    }

    func prepareDeletedPinRetirements(
        _ pinIds: Set<UUID>
    ) -> PreparedShortcutLiveTabRetirement? {
        transaction.prepareDeletedPinRetirements(pinIds)
    }

    func finish(
        _ prepared: PreparedShortcutLiveTabRetirement
    ) -> ShortcutLiveTabRetirementResult {
        let retiredIds: Set<UUID>
        if let committed = prepared.committedRuntimeRetirement {
            retiredIds = runtimeTeardown.retirement.publish(committed)
        } else {
            retiredIds = (prepared.runtimeTeardown.map(runtimeTeardown.finish) ?? [])
                .union(prepared.terminallyDrainedTabIDs)
        }
        assert(retiredIds == Set(prepared.result.retiredTabIds))
        guard prepared.windowCommitPolicy == .retirementService else {
            return prepared.result
        }
        var persistedWindowIds = Set<UUID>()
        if prepared.result.didClearCurrentSelection,
           let runtime = prepared.runtime {
            persistedWindowIds = runtime.validateWindowStates()
        }
        for windowState in prepared.result.windowStatesNeedingPersistence
            where persistedWindowIds.contains(windowState.id) == false {
            prepared.runtime?.persistWindowSession(for: windowState)
        }
        return prepared.result
    }

    func finishAfterCurrentBatch(
        _ prepared: PreparedShortcutLiveTabRetirement
    ) {
        structuralLookup.runAfterCurrentBatch { [self] in
            _ = finish(prepared)
        }
    }
}

extension ShortcutLiveTabRetirementService {
    convenience init(tabManager: TabManager) {
        self.init(
            registry: tabManager.liveShortcutTabs,
            batchRetirement: tabManager.liveShortcutTabBatchRetirement,
            structuralLookup: tabManager.structuralLookupCoordinator,
            runtimeConnection: tabManager.runtimePortConnection,
            runtimeTeardown: tabManager.runtimeTeardown
        )
    }
}
