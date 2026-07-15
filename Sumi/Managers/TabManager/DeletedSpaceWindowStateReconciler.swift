import Foundation

struct SpaceRemovalFootprint {
    let spaceId: UUID
    let tabIds: Set<UUID>
    let shortcutPinIds: Set<UUID>
    let retiredShortcutPinIDsByWindow: [UUID: Set<UUID>]
    let splitGroupIds: Set<UUID>
}

/// Removes references that generic selection validation cannot discover
/// because they live in per-Space history maps or deferred split state.
@MainActor
final class DeletedSpaceWindowStateReconciler {
    private let runtimePorts: () -> RuntimePortRegistry

    init(runtimePorts: @escaping () -> RuntimePortRegistry) {
        self.runtimePorts = runtimePorts
    }

    func runtimeLease() -> RuntimePortRegistry {
        runtimePorts()
    }

    func reconcile(
        _ removal: SpaceRemovalFootprint,
        using runtime: RuntimePortRegistry
    ) -> [BrowserWindowState] {
        var changedWindows: [BrowserWindowState] = []
        runtime.forEachWindowState { windowState in
            if DeletedSpaceWindowReferencePruner().removeReferences(
                to: removal,
                from: windowState
            ) {
                changedWindows.append(windowState)
            }
        }
        return changedWindows.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func finish(
        changedWindows: [BrowserWindowState],
        using runtime: RuntimePortRegistry
    ) {
        let persistedWindowIds = runtime.validateWindowStates()
        changedWindows
            .filter { persistedWindowIds.contains($0.id) == false }
            .forEach(runtime.persistWindowSession(for:))
    }
}
