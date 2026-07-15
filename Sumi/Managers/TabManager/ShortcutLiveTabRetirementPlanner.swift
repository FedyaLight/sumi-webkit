import Foundation

/// Atomically removes live registry leases and reconciles window selection,
/// while retaining the exact runtime needed by the later physical teardown.
@MainActor
final class ShortcutLiveTabRetirementPlanner {
    private let registry: LiveShortcutTabRegistry
    private let batchRetirement: LiveShortcutTabBatchRetirement

    init(
        registry: LiveShortcutTabRegistry,
        batchRetirement: LiveShortcutTabBatchRetirement
    ) {
        self.registry = registry
        self.batchRetirement = batchRetirement
    }

    func prepare(
        pinId: UUID,
        in windowId: UUID,
        using runtime: RuntimePortRegistry?
    ) -> PreparedShortcutLiveTabRetirement? {
        guard registry.tab(for: pinId, in: windowId) != nil else {
            return PreparedShortcutLiveTabRetirement(
                tabs: [],
                runtime: nil,
                result: ShortcutLiveTabRetirementResult()
            )
        }
        guard let runtime,
              let entry = registry.remove(pinId: pinId, in: windowId) else {
            return nil
        }
        var result = ShortcutLiveTabRetirementResult(
            retiredTabIds: [entry.tab.id]
        )
        if let windowState = runtime.windowState(for: windowId) {
            result.merge(
                ShortcutSelectionReconciler.reconcileRetiredInstance(
                    pinId: pinId,
                    tabId: entry.tab.id,
                    in: windowState
                )
            )
        }
        return PreparedShortcutLiveTabRetirement(
            tabs: [entry.tab],
            runtime: runtime,
            result: result
        )
    }

    func prepare(
        pinIds: Set<UUID>,
        in windowId: UUID,
        using runtime: RuntimePortRegistry?
    ) -> PreparedShortcutLiveTabRetirement? {
        let existingEntries = registry.entries(in: windowId).filter {
            pinIds.contains($0.pinId)
        }
        guard !existingEntries.isEmpty else {
            return PreparedShortcutLiveTabRetirement(
                tabs: [],
                runtime: nil,
                result: ShortcutLiveTabRetirementResult()
            )
        }
        guard let runtime else { return nil }

        let entries = batchRetirement.remove(pinIDs: pinIds, in: windowId)
        var result = ShortcutLiveTabRetirementResult(
            retiredTabIds: entries.map(\.tab.id)
        )
        if let windowState = runtime.windowState(for: windowId) {
            for entry in entries {
                result.merge(
                    ShortcutSelectionReconciler.reconcileRetiredInstance(
                        pinId: entry.pinId,
                        tabId: entry.tab.id,
                        in: windowState
                    )
                )
            }
        }
        return PreparedShortcutLiveTabRetirement(
            tabs: entries.map(\.tab),
            runtime: runtime,
            result: result
        )
    }

    func prepareDeletedPins(
        _ pinIds: Set<UUID>,
        using runtime: RuntimePortRegistry?
    ) -> PreparedShortcutLiveTabRetirement? {
        let orderedPinIds = pinIds.sorted { $0.uuidString < $1.uuidString }
        let existingEntries = orderedPinIds.flatMap(registry.entries(for:))
        guard existingEntries.isEmpty || runtime != nil else { return nil }

        let entries = batchRetirement.remove(pinIDs: pinIds)
        var result = ShortcutLiveTabRetirementResult(
            retiredTabIds: entries.map(\.tab.id)
        )
        if let runtime {
            reconcileRetiredEntries(entries, using: runtime, result: &result)
            for pinId in orderedPinIds {
                runtime.forEachWindowState {
                    result.merge(
                        ShortcutSelectionReconciler.reconcileDeletedPin(
                            pinId,
                            in: $0
                        )
                    )
                }
            }
        }
        return PreparedShortcutLiveTabRetirement(
            tabs: entries.map(\.tab),
            runtime: runtime,
            windowCommitPolicy: .retirementService,
            result: result
        )
    }

    private func reconcileRetiredEntries(
        _ entries: [LiveShortcutTabEntry],
        using runtime: RuntimePortRegistry,
        result: inout ShortcutLiveTabRetirementResult
    ) {
        for entry in entries {
            guard let windowState = runtime.windowState(for: entry.windowId) else {
                continue
            }
            result.merge(
                ShortcutSelectionReconciler.reconcileRetiredInstance(
                    pinId: entry.pinId,
                    tabId: entry.tab.id,
                    in: windowState
                )
            )
        }
    }
}
