import Foundation

@MainActor
protocol WindowWebContentBrowserContext: AnyObject {
    var sidebarDragState: SidebarDragState { get }

    func currentTab(for windowState: BrowserWindowState) -> Tab?
    func tab(for tabId: UUID) -> Tab?
    func splitGroup(for windowId: UUID) -> SplitGroup?
    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState)
    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    )
    func removeSplitGroup(id: UUID)
    func updateSplitLayoutSizes(
        groupId: UUID,
        path: [Int],
        sizes: [Double],
        for windowId: UUID
    )
    func configureSplitDropCapture(_ view: SplitDropCaptureView, windowId: UUID)
    func configureSplitControls(
        _ controls: SplitPaneControlsView,
        tab: Tab,
        windowState: BrowserWindowState
    )
}

@MainActor
final class BrowserManagerWindowWebContentContext: WindowWebContentBrowserContext {
    private let browserManager: BrowserManager
    let sidebarDragState: SidebarDragState

    init(
        browserManager: BrowserManager,
        sidebarDragState: SidebarDragState
    ) {
        self.browserManager = browserManager
        self.sidebarDragState = sidebarDragState
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        browserManager.shellRuntime.windowTabs.currentTab(for: windowState)
    }

    func tab(for tabId: UUID) -> Tab? {
        browserManager.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
    }

    func splitGroup(for windowId: UUID) -> SplitGroup? {
        browserManager.splitManager.splitGroup(for: windowId)
    }

    func removeSplitGroup(id: UUID) {
        browserManager.tabManager.splitGroupStructureOwner.removeSplitGroup(id: id)
    }

    func updateSplitLayoutSizes(
        groupId: UUID,
        path: [Int],
        sizes: [Double],
        for windowId: UUID
    ) {
        browserManager.splitManager.updateLayoutSizes(
            groupId: groupId,
            path: path,
            sizes: sizes,
            for: windowId
        )
    }

    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState) {
        browserManager.shellRuntime.windowVisuals.schedulePrepareVisibleWebViews(for: windowState)
    }

    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    ) {
        browserManager.shellRuntime.windowVisuals.enqueueWindowMutationDuringHistorySwipe(kind, for: windowState)
    }

    func configureSplitDropCapture(_ view: SplitDropCaptureView, windowId: UUID) {
        view.configure(
            runtime: SplitDropCaptureRuntime(
                splitManager: browserManager.splitManager,
                sidebarDragState: sidebarDragState,
                windowState: { [weak browserManager] windowId in
                    browserManager?.windowRegistry?.windows[windowId]
                },
                resolveDragTab: { [weak browserManager] tabId in
                    browserManager?.tabManager.sidebarDragRoutingOwner.resolveDragTab(for: tabId)
                }
            ),
            windowId: windowId
        )
    }

    func configureSplitControls(
        _ controls: SplitPaneControlsView,
        tab: Tab,
        windowState: BrowserWindowState
    ) {
        controls.configure(
            tab: tab,
            splitManager: browserManager.splitManager,
            windowState: windowState,
            sidebarDragState: sidebarDragState
        )
    }
}
