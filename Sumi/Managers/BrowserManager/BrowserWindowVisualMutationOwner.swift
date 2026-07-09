import Foundation

@MainActor
final class BrowserWindowVisualMutationOwner {
    private let hasActiveHistorySwipe: @MainActor (UUID) -> Bool
    private let currentTab: @MainActor (BrowserWindowState) -> Tab?
    private let performImmediateVisualHandoff: @MainActor (UUID) -> Bool
    private let prepareVisibleWebViewsHandler: @MainActor (BrowserWindowState) -> Bool
    private let schedulePrepareVisibleWebViewsHandler: @MainActor (BrowserWindowState) -> Void
    private let historySwipeWindowMutationFlushOwner = HistorySwipeWindowMutationFlushOwner()

    init(
        hasActiveHistorySwipe: @escaping @MainActor (UUID) -> Bool,
        currentTab: @escaping @MainActor (BrowserWindowState) -> Tab?,
        performImmediateVisualHandoffIfPossible: @escaping @MainActor (UUID) -> Bool,
        prepareVisibleWebViews: @escaping @MainActor (BrowserWindowState) -> Bool,
        schedulePrepareVisibleWebViews: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.hasActiveHistorySwipe = hasActiveHistorySwipe
        self.currentTab = currentTab
        self.performImmediateVisualHandoff = performImmediateVisualHandoffIfPossible
        self.prepareVisibleWebViewsHandler = prepareVisibleWebViews
        self.schedulePrepareVisibleWebViewsHandler = schedulePrepareVisibleWebViews
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
    func performImmediateVisualHandoffIfPossible(in windowState: BrowserWindowState) -> Bool {
        guard !isBackForwardGestureActive(in: windowState) else { return false }
        return performImmediateVisualHandoff(windowState.id)
    }

    @discardableResult
    func prepareVisibleWebViews(for windowState: BrowserWindowState) -> Bool {
        prepareVisibleWebViewsHandler(windowState)
    }

    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState) {
        guard !isBackForwardGestureActive(in: windowState) else {
            enqueueWindowMutationDuringHistorySwipe(
                .prepareVisibleWebViews,
                for: windowState
            )
            return
        }
        schedulePrepareVisibleWebViewsHandler(windowState)
    }

    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    ) {
        historySwipeWindowMutationFlushOwner.enqueue(kind, for: windowState)
    }

    func flushWindowMutationsAfterHistorySwipe(in windowId: UUID) {
        historySwipeWindowMutationFlushOwner.flushPendingMutations(
            in: windowId,
            prepareVisibleWebViews: { [prepareVisibleWebViewsHandler] windowState in
                prepareVisibleWebViewsHandler(windowState)
            },
            refreshCompositor: { windowState in
                windowState.compositorInvalidation.refresh()
            }
        )
    }

    func cancelWindowMutationsAfterHistorySwipe(in windowId: UUID) {
        historySwipeWindowMutationFlushOwner.cancelPendingMutations(in: windowId)
    }

    private func isBackForwardGestureActive(in windowState: BrowserWindowState) -> Bool {
        if hasActiveHistorySwipe(windowState.id) {
            return true
        }
        guard let currentTab = currentTab(windowState) else { return false }
        return currentTab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind == .backForward
            || currentTab.navigationRuntime.navigationTransactionOwner.isFreezingNavDuringBackForwardGesture
    }
}
