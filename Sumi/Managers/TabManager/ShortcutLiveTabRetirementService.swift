import Foundation

/// Commits planned shortcut retirement and performs physical runtime release
/// only after the outermost structural transaction publishes its final model.
@MainActor
final class ShortcutLiveTabRetirementService {
    private let registry: LiveShortcutTabRegistry
    private let planner: ShortcutLiveTabRetirementPlanner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let runtimeTeardown: TabRuntimeTeardownService

    init(
        registry: LiveShortcutTabRegistry,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimePorts: @escaping () -> RuntimePortRegistry?,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        self.registry = registry
        planner = ShortcutLiveTabRetirementPlanner(
            registry: registry,
            runtimePorts: runtimePorts
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
            planner.prepare(pinId: pinId, in: windowId)
        }
    }

    func retireDeletedPin(_ pinId: UUID) -> ShortcutLiveTabRetirementResult {
        guard let prepared = structuralLookup.withTransaction({
            planner.prepareDeletedPins([pinId])
        }) else { return ShortcutLiveTabRetirementResult() }
        finishAfterCurrentBatch(prepared)
        return prepared.result
    }

    func prepareRetirement(
        pinId: UUID,
        in windowId: UUID
    ) -> PreparedShortcutLiveTabRetirement? {
        planner.prepare(pinId: pinId, in: windowId)
    }

    func prepareRetirements(
        pinIds: Set<UUID>,
        in windowId: UUID
    ) -> PreparedShortcutLiveTabRetirement? {
        planner.prepare(pinIds: pinIds, in: windowId)
    }

    func prepareDeletedPinRetirement(
        _ pinId: UUID
    ) -> PreparedShortcutLiveTabRetirement? {
        planner.prepareDeletedPins([pinId])
    }

    func prepareDeletedPinRetirements(
        _ pinIds: Set<UUID>
    ) -> PreparedShortcutLiveTabRetirement? {
        planner.prepareDeletedPins(pinIds)
    }

    func finish(
        _ prepared: PreparedShortcutLiveTabRetirement
    ) -> ShortcutLiveTabRetirementResult {
        let retiredIds = prepared.runtime.map {
            runtimeTeardown.teardown(prepared.tabs, using: $0)
        } ?? []
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
            structuralLookup: tabManager.structuralLookupCoordinator,
            runtimePorts: { [weak tabManager] in tabManager?.runtimePorts },
            runtimeTeardown: tabManager.runtimeTeardown
        )
    }
}
