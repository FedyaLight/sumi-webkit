import Foundation
import SumiBrowserCore

@MainActor
struct LiveTabSplitCoordinationPort: TabSplitCoordinationPort {
    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func handleTabClosure(_ tabId: UUID) {
        browserManager?.splitManager.handleTabClosure(tabId)
    }

    func visibleSplitTabIds(for windowId: UUID) -> [UUID] {
        browserManager?.splitManager.visibleTabIds(for: windowId) ?? []
    }

    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        browserManager?.splitManager.isTabVisibleInSplit(tabId, in: windowId) == true
    }

    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        browserManager?.splitManager.isTabActiveInSplit(tabId, in: windowId) == true
    }

    func updateActiveSplitSide(for tabId: UUID, in windowId: UUID) {
        browserManager?.splitManager.updateActiveSide(for: tabId, in: windowId)
    }
}
