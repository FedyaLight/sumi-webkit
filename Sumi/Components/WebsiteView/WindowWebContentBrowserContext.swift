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
    private let windowTabs: BrowserWindowTabContext
    private let membership: TabCollectionMembershipOwner
    private let windowVisuals: BrowserWindowVisualCoordinator

    init(
        windowTabs: BrowserWindowTabContext,
        membership: TabCollectionMembershipOwner,
        windowVisuals: BrowserWindowVisualCoordinator
    ) {
        self.windowTabs = windowTabs
        self.membership = membership
        self.windowVisuals = windowVisuals
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        windowTabs.currentTab(for: windowState)
    }

    func tab(for tabId: UUID) -> Tab? {
        membership.tab(for: tabId)
    }

    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState) {
        windowVisuals.schedulePrepareVisibleWebViews(for: windowState)
    }

    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    ) {
        windowVisuals.enqueueWindowMutationDuringHistorySwipe(kind, for: windowState)
    }
}
