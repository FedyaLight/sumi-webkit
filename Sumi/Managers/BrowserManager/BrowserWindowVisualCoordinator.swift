import Foundation

/// Coordinates window-scoped compositor invalidation, visible WebView
/// preparation, and mutations deferred by a back/forward gesture.
@MainActor
final class BrowserWindowVisualCoordinator {
    private let protection: WebViewProtectionRuntime
    private let windowTabs: BrowserWindowTabContext
    private let compositor: WebViewCompositorRuntime
    private let visiblePreparation: WebViewVisiblePreparationService
    private let historySwipeMutations = HistorySwipeWindowMutationFlushOwner()

    init(
        protection: WebViewProtectionRuntime,
        windowTabs: BrowserWindowTabContext,
        compositor: WebViewCompositorRuntime,
        visiblePreparation: WebViewVisiblePreparationService
    ) {
        self.protection = protection
        self.windowTabs = windowTabs
        self.compositor = compositor
        self.visiblePreparation = visiblePreparation
    }

    func refreshCompositor(for windowState: BrowserWindowState) {
        guard !isBackForwardGestureActive(in: windowState) else {
            enqueueWindowMutationDuringHistorySwipe(
                .refreshCompositor,
                for: windowState
            )
            return
        }
        windowState.compositorInvalidation.refresh()
    }

    @discardableResult
    func performImmediateVisualHandoffIfPossible(
        in windowState: BrowserWindowState
    ) -> Bool {
        guard !isBackForwardGestureActive(in: windowState) else { return false }
        return compositor.performImmediateVisualHandoffIfPossible(
            in: windowState.id
        )
    }

    @discardableResult
    func prepareVisibleWebViews(for windowState: BrowserWindowState) -> Bool {
        visiblePreparation.prepare(for: windowState)
    }

    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState) {
        guard !isBackForwardGestureActive(in: windowState) else {
            enqueueWindowMutationDuringHistorySwipe(
                .prepareVisibleWebViews,
                for: windowState
            )
            return
        }
        visiblePreparation.schedule(for: windowState)
    }

    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    ) {
        historySwipeMutations.enqueue(kind, for: windowState)
    }

    func flushWindowMutationsAfterHistorySwipe(in windowId: UUID) {
        historySwipeMutations.flushPendingMutations(
            in: windowId,
            prepareVisibleWebViews: { [visiblePreparation] windowState in
                visiblePreparation.prepare(for: windowState)
            },
            refreshCompositor: { windowState in
                windowState.compositorInvalidation.refresh()
            }
        )
    }

    func cancelWindowMutationsAfterHistorySwipe(in windowId: UUID) {
        historySwipeMutations.cancelPendingMutations(in: windowId)
    }

    private func isBackForwardGestureActive(
        in windowState: BrowserWindowState
    ) -> Bool {
        if protection.hasActiveHistorySwipe(in: windowState.id) {
            return true
        }
        guard let currentTab = windowTabs.currentTab(for: windowState) else {
            return false
        }
        let navigation = currentTab.navigationRuntime.navigationTransactionOwner
        return navigation.pendingMainFrameNavigationKind == .backForward
            || navigation.isFreezingNavDuringBackForwardGesture
    }
}
