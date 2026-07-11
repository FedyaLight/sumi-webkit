import Foundation

/// Atomically removes live registry leases and reconciles window selection,
/// while retaining the exact runtime needed by the later physical teardown.
@MainActor
final class ShortcutLiveTabRetirementPlanner {
    private let registry: LiveShortcutTabRegistry
    private let runtimePorts: () -> RuntimePortRegistry?

    init(
        registry: LiveShortcutTabRegistry,
        runtimePorts: @escaping () -> RuntimePortRegistry?
    ) {
        self.registry = registry
        self.runtimePorts = runtimePorts
    }

    func prepare(
        pinId: UUID,
        in windowId: UUID
    ) -> PreparedShortcutLiveTabRetirement? {
        guard registry.tab(for: pinId, in: windowId) != nil else {
            return PreparedShortcutLiveTabRetirement(
                tabs: [],
                runtime: nil,
                result: ShortcutLiveTabRetirementResult()
            )
        }
        guard let runtime = runtimePorts(),
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
        in windowId: UUID
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
        guard let runtime = runtimePorts() else { return nil }

        let entries = registry.removeAll(pinIds: pinIds, in: windowId)
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
        _ pinIds: Set<UUID>
    ) -> PreparedShortcutLiveTabRetirement? {
        let orderedPinIds = pinIds.sorted { $0.uuidString < $1.uuidString }
        let existingEntries = orderedPinIds.flatMap(registry.entries(for:))
        let runtime = runtimePorts()
        guard existingEntries.isEmpty || runtime != nil else { return nil }

        let entries = registry.removeAll(pinIds: pinIds)
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
        _ entries: [LiveShortcutTabRegistry.Entry],
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
