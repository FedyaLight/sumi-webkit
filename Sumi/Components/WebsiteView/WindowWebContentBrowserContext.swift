import Foundation

@MainActor
protocol WindowWebContentBrowserContext: AnyObject {
    func currentTab(for windowState: BrowserWindowState) -> Tab?
    func tab(for tabId: UUID) -> Tab?
    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState)
    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    )
}

@MainActor
final class BrowserManagerWindowWebContentContext: WindowWebContentBrowserContext {
    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
    }

    func tab(for tabId: UUID) -> Tab? {
        browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
    }

    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState) {
        browserManager?.shellRuntime.windowVisuals.schedulePrepareVisibleWebViews(for: windowState)
    }

    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    ) {
        browserManager?.shellRuntime.windowVisuals.enqueueWindowMutationDuringHistorySwipe(kind, for: windowState)
    }

}
