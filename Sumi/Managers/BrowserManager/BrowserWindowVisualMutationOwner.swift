import Foundation

@MainActor
final class BrowserWindowVisualMutationOwner {
    struct Dependencies {
        let hasActiveHistorySwipe: @MainActor (UUID) -> Bool
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let performImmediateVisualHandoffIfPossible: @MainActor (UUID) -> Bool
        let prepareVisibleWebViews: @MainActor (BrowserWindowState) -> Bool
        let schedulePrepareVisibleWebViews: @MainActor (BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies
    private let historySwipeWindowMutationFlushOwner = HistorySwipeWindowMutationFlushOwner()

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func refreshCompositor(for windowState: BrowserWindowState) {
        guard !isBackForwardGestureActive(in: windowState) else {
            enqueueWindowMutationDuringHistorySwipe(
                .refreshCompositor,
                for: windowState
            )
            return
        }
        windowState.refreshCompositor()
    }

    @discardableResult
    func performImmediateVisualHandoffIfPossible(in windowState: BrowserWindowState) -> Bool {
        guard !isBackForwardGestureActive(in: windowState) else { return false }
        return dependencies.performImmediateVisualHandoffIfPossible(windowState.id)
    }

    @discardableResult
    func prepareVisibleWebViews(for windowState: BrowserWindowState) -> Bool {
        dependencies.prepareVisibleWebViews(windowState)
    }

    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState) {
        guard !isBackForwardGestureActive(in: windowState) else {
            enqueueWindowMutationDuringHistorySwipe(
                .prepareVisibleWebViews,
                for: windowState
            )
            return
        }
        dependencies.schedulePrepareVisibleWebViews(windowState)
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
            prepareVisibleWebViews: { [dependencies] windowState in
                dependencies.prepareVisibleWebViews(windowState)
            },
            refreshCompositor: { windowState in
                windowState.refreshCompositor()
            }
        )
    }

    func cancelWindowMutationsAfterHistorySwipe(in windowId: UUID) {
        historySwipeWindowMutationFlushOwner.cancelPendingMutations(in: windowId)
    }

    private func isBackForwardGestureActive(in windowState: BrowserWindowState) -> Bool {
        if dependencies.hasActiveHistorySwipe(windowState.id) {
            return true
        }
        guard let currentTab = dependencies.currentTab(windowState) else { return false }
        return currentTab.pendingMainFrameNavigationKind == .backForward
            || currentTab.isFreezingNavDuringBackForwardGesture
    }
}
