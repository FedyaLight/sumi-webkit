import Foundation

@MainActor
final class SidebarDraggedTabSplitRetirementTransaction {
    private let runtimeConnection: TabRuntimePortConnection

    init(runtimeConnection: TabRuntimePortConnection) {
        self.runtimeConnection = runtimeConnection
    }

    func dissolveActiveSplitIfNeeded(for tab: Tab) {
        guard !tab.isShortcutLiveInstance else { return }

        let lease = runtimeConnection.captureLease()
        let runtimePorts = runtimeConnection.requireLease()
        precondition(
            runtimeConnection.accepts(lease),
            "Sidebar split retirement requires one runtime attachment generation"
        )
        runtimePorts.forEachWindow { windowID, _ in
            precondition(
                runtimeConnection.accepts(lease),
                "Runtime attachment changed during sidebar split retirement"
            )
            if runtimePorts.visibleSplitTabIds(for: windowID).contains(tab.id) {
                runtimePorts.handleTabClosure(tab.id)
            }
        }
        precondition(
            runtimeConnection.accepts(lease),
            "Runtime attachment changed during sidebar split retirement"
        )
    }
}
