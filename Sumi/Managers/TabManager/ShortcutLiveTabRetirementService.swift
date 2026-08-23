import Foundation

@MainActor
final class ShortcutLiveTabRetirementService {
    private let registry: LiveShortcutTabRegistry
    private let structuralLookup: TabStructuralLookupCoordinator
    private let batch: ShortcutLiveRetirementBatchTransaction

    init(
        registry: LiveShortcutTabRegistry,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeConnection: TabRuntimePortConnection,
        runtimeTeardown: TabRuntimeTeardownService,
        windowMutations: BrowserWindowShortcutMutationOwner,
        splitGroups: SplitGroupStore,
        splitMutations: SplitGroupMutationService
    ) {
        self.registry = registry
        self.structuralLookup = structuralLookup
        batch = ShortcutLiveRetirementBatchTransaction(
            registry: registry,
            structuralLookup: structuralLookup,
            runtimeConnection: runtimeConnection,
            windowMutations: windowMutations,
            splitGroups: splitGroups,
            splitMutations: splitMutations,
            teardown: runtimeTeardown
        )
    }

    func retire(tabId: UUID) -> ShortcutLiveTabRetirementResult? {
        guard let entry = registry.entry(tabId: tabId) else { return nil }
        return retire(pinId: entry.pinId, in: entry.windowId)
    }

    func retire(
        pinId: UUID,
        in windowId: UUID
    ) -> ShortcutLiveTabRetirementResult {
        var prepared: PreparedShortcutLiveRetirementBatch?
        structuralLookup.withTransaction {
            prepared = self.prepared(from: batch.prepareWindowRetirement(
                pinIDs: [pinId], in: windowId
            ))
            if let prepared { finishAfterCurrentBatch(prepared) }
        }
        return prepared?.result ?? .init()
    }

    func prepareRetirement(
        pinId: UUID,
        in windowId: UUID,
        targetWindowState: BrowserWindowShortcutMutationState? = nil
    ) -> PreparedShortcutLiveRetirementBatch? {
        structuralLookup.withTransaction {
            prepared(from: batch.prepareWindowRetirement(
                pinIDs: [pinId],
                in: windowId,
                targetWindowState: targetWindowState
            ))
        }
    }

    func prepareRetirements(
        pinIds: Set<UUID>,
        in windowId: UUID,
        targetWindowState: BrowserWindowShortcutMutationState? = nil
    ) -> PreparedShortcutLiveRetirementBatch? {
        structuralLookup.withTransaction {
            prepared(from: batch.prepareWindowRetirement(
                pinIDs: pinIds,
                in: windowId,
                targetWindowState: targetWindowState
            ))
        }
    }

    func prepareDeletedPinRetirement(
        _ pinId: UUID,
        targetWindowStates: [UUID: BrowserWindowShortcutMutationState] = [:]
    ) -> PreparedShortcutLiveRetirementBatch? {
        structuralLookup.withTransaction {
            prepared(from: batch.prepareDeletedPins(
                [pinId], targetWindowStates: targetWindowStates
            ))
        }
    }

    func prepareDeletedPinRetirements(
        _ pinIds: Set<UUID>,
        targetWindowStates: [UUID: BrowserWindowShortcutMutationState] = [:]
    ) -> PreparedShortcutLiveRetirementBatch? {
        structuralLookup.withTransaction {
            prepared(from: batch.prepareDeletedPins(
                pinIds, targetWindowStates: targetWindowStates
            ))
        }
    }

    func prepareTerminalEffect(
        _ prepared: PreparedShortcutLiveTabRetirement
    ) -> PreparedShortcutLiveTabRetirementTerminalEffect? {
        prepared.terminalEffect
    }

    func finish(
        _ prepared: PreparedShortcutLiveRetirementBatch
    ) -> ShortcutLiveTabRetirementResult {
        finishAfterCurrentBatch(prepared)
        return prepared.result
    }

    func finishAfterCurrentBatch(
        _ prepared: PreparedShortcutLiveRetirementBatch
    ) {
        structuralLookup.runAfterCurrentBatch {
            prepared.publishTerminalEffects()
        }
    }

    private func prepared(
        from outcome: ShortcutLiveRetirementBatchPreparation
    ) -> PreparedShortcutLiveRetirementBatch? {
        switch outcome {
        case .prepared(let prepared): return prepared
        case .noEffect: return PreparedShortcutLiveRetirementBatch()
        case .rejected: return nil
        }
    }
}
