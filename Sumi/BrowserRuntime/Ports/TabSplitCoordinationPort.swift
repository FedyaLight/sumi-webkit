import Foundation

@MainActor
protocol TabSplitCoordinationPort {
    func handleTabClosure(_ tabId: UUID)
    func visibleSplitTabIds(for windowId: UUID) -> [UUID]
    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool
    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool
    func updateActiveSplitSide(for tabId: UUID, in windowId: UUID)
}

@MainActor
struct LiveTabSplitCoordinationPort: TabSplitCoordinationPort {
    private let runtime: BrowserManagerRuntimeReference

    init(runtime: BrowserManagerRuntimeReference) {
        self.runtime = runtime
    }

    func handleTabClosure(_ tabId: UUID) {
        runtime.require().splitManager.handleTabClosure(tabId)
    }

    func visibleSplitTabIds(for windowId: UUID) -> [UUID] {
        runtime.require().splitManager.visibleTabIds(for: windowId)
    }

    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        runtime.require().splitManager.isTabVisibleInSplit(tabId, in: windowId)
    }

    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        runtime.require().splitManager.isTabActiveInSplit(tabId, in: windowId)
    }

    func updateActiveSplitSide(for tabId: UUID, in windowId: UUID) {
        runtime.require().splitManager.updateActiveSide(for: tabId, in: windowId)
    }
}
