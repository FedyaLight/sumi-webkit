import Foundation

/// Terminal presentation half of an already-committed split closure. Runtime
/// cleanup owns this receipt and publishes only after the retired Tab can no
/// longer affect a same-UUID replacement.
@MainActor
protocol TabSplitClosureSettlement: AnyObject {
    func publish()
}

@MainActor
protocol TabSplitCoordinationPort {
    func handleTabClosure(_ tabId: UUID)
    func stageTabClosures(
        _ tabIds: Set<UUID>
    ) -> (any TabSplitClosureSettlement)?
    func visibleSplitTabIds(for windowId: UUID) -> [UUID]
    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool
    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool
}

extension TabSplitCoordinationPort {
    func handleTabClosure(_ tabId: UUID) {
        stageTabClosures([tabId])?.publish()
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

    func stageTabClosures(
        _ tabIds: Set<UUID>
    ) -> (any TabSplitClosureSettlement)? {
        tabClosures.stage(tabIds)
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
