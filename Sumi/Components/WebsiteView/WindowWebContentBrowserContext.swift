import Foundation
import SumiDomain

@MainActor
protocol WindowWebContentBrowserContext: AnyObject {
    var sidebarDragState: SidebarDragState { get }

    func currentTab(for windowState: BrowserWindowState) -> Tab?
    func tab(for tabId: UUID) -> Tab?
    func splitResolution(for windowState: BrowserWindowState) -> WindowSplitResolution
    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState)
    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    )
    func updateSplitLayoutWeights(
        expectedGroup: SumiDomain.SplitGroup,
        path: [Int],
        weights: [Double],
        for windowID: UUID
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
    private weak var browserManager: BrowserManager?
    private let splitProjection: WindowSplitProjection
    let sidebarDragState: SidebarDragState

    init(
        browserManager: BrowserManager,
        splitProjection: WindowSplitProjection,
        sidebarDragState: SidebarDragState
    ) {
        self.browserManager = browserManager
        self.splitProjection = splitProjection
        self.sidebarDragState = sidebarDragState
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
    }

    func tab(for tabId: UUID) -> Tab? {
        browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
    }

    func splitResolution(
        for windowState: BrowserWindowState
    ) -> WindowSplitResolution {
        splitProjection.resolve(
            selection: windowState.splitSelection,
            in: windowState.id
        )
    }

    func updateSplitLayoutWeights(
        expectedGroup: SumiDomain.SplitGroup,
        path: [Int],
        weights: [Double],
        for windowID: UUID
    ) {
        browserManager?.splitManager.updateSplitLayoutWeights(
            expectedGroup: expectedGroup,
            path: path,
            weights: weights,
            for: windowID
        )
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

    func configureSplitDropCapture(_ view: SplitDropCaptureView, windowId: UUID) {
        guard let browserManager else { return }
        view.configure(
            runtime: SplitDropCaptureRuntime(
                splitManager: browserManager.splitManager,
                sidebarDragState: sidebarDragState,
                windowState: { [weak browserManager] windowId in
                    browserManager?.windowRegistry?.windows[windowId]
                },
                resolveDragTab: { [weak browserManager] item in
                    browserManager?.tabManager.sidebarDragRouter
                        .resolveDragTab(for: item)
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
        guard let browserManager else { return }
        controls.configure(
            tab: tab,
            splitManager: browserManager.splitManager,
            windowState: windowState,
            sidebarDragState: sidebarDragState
        )
    }
}
