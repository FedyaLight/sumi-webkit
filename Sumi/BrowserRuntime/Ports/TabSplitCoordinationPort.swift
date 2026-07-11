import Foundation

@MainActor
protocol TabSplitCoordinationPort {
    func handleTabClosure(_ tabId: UUID)
    func handleTabClosures(_ tabIds: Set<UUID>)
    func visibleSplitTabIds(for windowId: UUID) -> [UUID]
    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool
    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool
}

extension TabSplitCoordinationPort {
    func handleTabClosures(_ tabIds: Set<UUID>) {
        for tabId in tabIds {
            handleTabClosure(tabId)
        }
    }
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

    func handleTabClosures(_ tabIds: Set<UUID>) {
        runtime.require().splitManager.handleTabClosures(tabIds)
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

}
