import Foundation

/// Deterministic read-only projection of windows selecting or displaying a tab.
@MainActor
final class ShortcutTabWindowQuery {
    private let runtimeConnection: TabRuntimePortConnection

    init(runtimeConnection: TabRuntimePortConnection) {
        self.runtimeConnection = runtimeConnection
    }

    func windowIdsSelecting(tabId: UUID, preferredWindowId: UUID? = nil) -> [UUID] {
        guard let runtime = runtimeConnection.captureLease().registry else {
            return []
        }
        return windowIdsSelecting(
            tabId: tabId,
            preferredWindowId: preferredWindowId,
            using: runtime
        )
    }

    func windowIdsSelecting(
        tabId: UUID,
        preferredWindowId: UUID?,
        using runtime: RuntimePortRegistry
    ) -> [UUID] {
        orderedWindowIds(
            tabId: tabId,
            preferredWindowId: preferredWindowId,
            prefersPrimary: true,
            runtime: runtime
        ) { _, state, _ in
            state.currentTabId == tabId
        }
    }

    func windowIdsDisplaying(tabId: UUID, preferredWindowId: UUID? = nil) -> [UUID] {
        guard let runtime = runtimeConnection.captureLease().registry else {
            return []
        }
        return windowIdsDisplaying(
            tabId: tabId,
            preferredWindowId: preferredWindowId,
            using: runtime
        )
    }

    func windowIdsDisplaying(
        tabId: UUID,
        preferredWindowId: UUID?,
        using runtime: RuntimePortRegistry
    ) -> [UUID] {
        orderedWindowIds(
            tabId: tabId,
            preferredWindowId: preferredWindowId,
            prefersPrimary: false,
            runtime: runtime
        ) { windowId, state, runtime in
            state.currentTabId == tabId
                || runtime.visibleSplitTabIds(for: windowId).contains(tabId)
        }
    }

    func windowStateDisplaying(tabId: UUID) -> BrowserWindowState? {
        let lease = runtimeConnection.captureLease()
        guard let runtime = lease.registry,
              let windowId = windowIdsDisplaying(
                  tabId: tabId,
                  preferredWindowId: nil,
                  using: runtime
              ).first else { return nil }
        return runtime.windowState(for: windowId)
    }

    private func orderedWindowIds(
        tabId: UUID,
        preferredWindowId: UUID?,
        prefersPrimary: Bool,
        runtime: RuntimePortRegistry,
        matches: (UUID, BrowserWindowState, RuntimePortRegistry) -> Bool
    ) -> [UUID] {
        let primaryWindowId = runtime.webViewLifecycle.primaryTrackedWindowId(
            for: tabId
        )
        let preferred = prefersPrimary
            ? [primaryWindowId, preferredWindowId]
            : [preferredWindowId, primaryWindowId]
        var result: [UUID] = []

        for windowId in preferred.compactMap(\.self) {
            guard result.contains(windowId) == false,
                  let state = runtime.windowState(for: windowId),
                  matches(windowId, state, runtime) else { continue }
            result.append(windowId)
        }

        var remaining: [UUID] = []
        runtime.forEachWindow { windowId, state in
            guard result.contains(windowId) == false,
                  matches(windowId, state, runtime) else { return }
            remaining.append(windowId)
        }
        result.append(contentsOf: remaining.sorted { $0.uuidString < $1.uuidString })
        return result
    }
}
