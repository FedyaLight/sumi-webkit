import Foundation

/// Prepares physical teardown, revalidates live registry identity, then commits
/// the matching shortcut structure through the planner.
@MainActor
final class ShortcutLiveTabRetirementTransaction {
    private let registry: LiveShortcutTabRegistry
    private let planner: ShortcutLiveTabRetirementPlanner
    private let runtimePorts: () -> RuntimePortRegistry?
    private let runtimeTeardown: TabRuntimeTeardownService

    init(
        registry: LiveShortcutTabRegistry,
        runtimePorts: @escaping () -> RuntimePortRegistry?,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        self.registry = registry
        planner = ShortcutLiveTabRetirementPlanner(registry: registry)
        self.runtimePorts = runtimePorts
        self.runtimeTeardown = runtimeTeardown
    }

    func prepareRetirement(
        pinId: UUID,
        in windowId: UUID
    ) -> PreparedShortcutLiveTabRetirement? {
        prepare(
            tabs: registry.tab(for: pinId, in: windowId).map { [$0] } ?? [],
            currentTabs: {
                registry.tab(for: pinId, in: windowId).map { [$0] } ?? []
            }
        ) { runtime in
            planner.prepare(pinId: pinId, in: windowId, using: runtime)
        }
    }

    func prepareRetirements(
        pinIds: Set<UUID>,
        in windowId: UUID
    ) -> PreparedShortcutLiveTabRetirement? {
        prepare(
            tabs: entries(pinIds: pinIds, in: windowId).map(\.tab),
            currentTabs: { self.entries(pinIds: pinIds, in: windowId).map(\.tab) }
        ) { runtime in
            planner.prepare(pinIds: pinIds, in: windowId, using: runtime)
        }
    }

    func prepareDeletedPinRetirements(
        _ pinIds: Set<UUID>
    ) -> PreparedShortcutLiveTabRetirement? {
        prepare(
            tabs: entries(pinIds: pinIds).map(\.tab),
            currentTabs: { self.entries(pinIds: pinIds).map(\.tab) }
        ) { runtime in
            planner.prepareDeletedPins(pinIds, using: runtime)
        }
    }

    private func prepare(
        tabs: [Tab],
        currentTabs: () -> [Tab],
        commit: (RuntimePortRegistry?) -> PreparedShortcutLiveTabRetirement?
    ) -> PreparedShortcutLiveTabRetirement? {
        guard sameIdentity(tabs, currentTabs()) else { return nil }
        guard tabs.isEmpty == false else { return commit(runtimePorts()) }
        guard let runtime = runtimePorts(),
              let teardown = runtimeTeardown.preparation.prepare(
                  tabs,
                  using: runtime
              ),
              sameIdentity(tabs, currentTabs()),
              let prepared = commit(runtime) else { return nil }
        return PreparedShortcutLiveTabRetirement(
            tabs: prepared.tabs,
            runtime: prepared.runtime,
            runtimeTeardown: teardown,
            windowCommitPolicy: prepared.windowCommitPolicy,
            result: prepared.result
        )
    }

    private func entries(
        pinIds: Set<UUID>,
        in windowId: UUID
    ) -> [LiveShortcutTabRegistry.Entry] {
        registry.entries(in: windowId).filter { pinIds.contains($0.pinId) }
    }

    private func entries(
        pinIds: Set<UUID>
    ) -> [LiveShortcutTabRegistry.Entry] {
        pinIds.flatMap { registry.entries(for: $0) }
    }

    private func sameIdentity(_ lhs: [Tab], _ rhs: [Tab]) -> Bool {
        lhs.count == rhs.count && Set(lhs.map(ObjectIdentifier.init))
            == Set(rhs.map(ObjectIdentifier.init))
    }
}
