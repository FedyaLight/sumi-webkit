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
    private let tabClosures: SplitTabClosureService
    private let query: WindowSplitQuery

    init(
        tabClosures: SplitTabClosureService,
        query: WindowSplitQuery
    ) {
        self.tabClosures = tabClosures
        self.query = query
    }

    func handleTabClosure(_ tabId: UUID) {
        tabClosures.handle(tabId)
    }

    func handleTabClosures(_ tabIds: Set<UUID>) {
        tabClosures.handle(tabIds)
    }

    func visibleSplitTabIds(for windowId: UUID) -> [UUID] {
        query.visibleTabIDs(in: windowId)
    }

    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        query.contains(tabID: tabId, in: windowId)
    }

    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        query.isActive(tabID: tabId, in: windowId)
    }
}
