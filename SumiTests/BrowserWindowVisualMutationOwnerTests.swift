import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowVisualMutationOwnerTests: XCTestCase {
    func testRefreshCompositorDefersDuringTabBackForwardNavigationUntilFlush() async {
        let windowState = BrowserWindowState()
        let tab = Tab()
        tab.pendingMainFrameNavigationKind = .backForward
        let owner = makeOwner(currentTab: { tab })

        owner.refreshCompositor(for: windowState)
        await drainMainQueue()

        XCTAssertEqual(windowState.compositorVersion, 0)

        owner.flushWindowMutationsAfterHistorySwipe(in: windowState.id)
        await drainMainQueue()

        XCTAssertEqual(windowState.compositorVersion, 1)
    }

    func testRefreshCompositorDefersDuringFrozenBackForwardNavigationUntilFlush() async {
        let windowState = BrowserWindowState()
        let tab = Tab()
        tab.isFreezingNavigationStateDuringBackForwardGesture = true
        let owner = makeOwner(currentTab: { tab })

        owner.refreshCompositor(for: windowState)
        await drainMainQueue()

        XCTAssertEqual(windowState.compositorVersion, 0)

        owner.flushWindowMutationsAfterHistorySwipe(in: windowState.id)
        await drainMainQueue()

        XCTAssertEqual(windowState.compositorVersion, 1)
    }

    func testSchedulePrepareVisibleWebViewsDefersDuringActiveHistorySwipeAndFlushesBeforeRefresh() async {
        let windowState = BrowserWindowState()
        var hasActiveHistorySwipe = true
        var events: [String] = []
        let owner = makeOwner(
            hasActiveHistorySwipe: { hasActiveHistorySwipe },
            prepareVisibleWebViews: {
                events.append("prepare")
                return true
            },
            schedulePrepareVisibleWebViews: { _ in
                events.append("schedule")
            }
        )

        owner.schedulePrepareVisibleWebViews(for: windowState)
        await drainMainQueue()

        XCTAssertEqual(events, [])
        XCTAssertEqual(windowState.compositorVersion, 0)

        hasActiveHistorySwipe = false
        owner.flushWindowMutationsAfterHistorySwipe(in: windowState.id)
        await drainMainQueue()

        XCTAssertEqual(events, ["prepare"])
        XCTAssertEqual(windowState.compositorVersion, 1)
    }

    func testImmediateVisualHandoffReturnsFalseDuringActiveHistorySwipe() {
        let owner = makeOwner(
            hasActiveHistorySwipe: { true },
            performImmediateVisualHandoffIfPossible: {
                XCTFail("Handoff should not be attempted during an active history swipe")
                return true
            }
        )

        XCTAssertFalse(owner.performImmediateVisualHandoffIfPossible(in: BrowserWindowState()))
    }

    func testSchedulePrepareVisibleWebViewsRunsImmediatelyWhenGestureInactive() {
        let windowState = BrowserWindowState()
        var scheduledWindowIds: [UUID] = []
        let owner = makeOwner(
            schedulePrepareVisibleWebViews: {
                scheduledWindowIds.append($0.id)
            }
        )

        owner.schedulePrepareVisibleWebViews(for: windowState)

        XCTAssertEqual(scheduledWindowIds, [windowState.id])
    }

    func testCancelDropsDeferredWindowMutation() async {
        let windowState = BrowserWindowState()
        let owner = makeOwner(hasActiveHistorySwipe: { true })

        owner.refreshCompositor(for: windowState)
        owner.cancelWindowMutationsAfterHistorySwipe(in: windowState.id)
        owner.flushWindowMutationsAfterHistorySwipe(in: windowState.id)
        await drainMainQueue()

        XCTAssertEqual(windowState.compositorVersion, 0)
    }

    private func makeOwner(
        hasActiveHistorySwipe: @escaping @MainActor () -> Bool = { false },
        currentTab: @escaping @MainActor () -> Tab? = { nil },
        performImmediateVisualHandoffIfPossible: @escaping @MainActor () -> Bool = { true },
        prepareVisibleWebViews: @escaping @MainActor () -> Bool = { false },
        schedulePrepareVisibleWebViews: @escaping @MainActor (BrowserWindowState) -> Void = { _ in }
    ) -> BrowserWindowVisualMutationOwner {
        BrowserWindowVisualMutationOwner(
            dependencies: BrowserWindowVisualMutationOwner.Dependencies(
                hasActiveHistorySwipe: { _ in hasActiveHistorySwipe() },
                currentTab: { _ in currentTab() },
                performImmediateVisualHandoffIfPossible: { _ in
                    performImmediateVisualHandoffIfPossible()
                },
                prepareVisibleWebViews: { _ in prepareVisibleWebViews() },
                schedulePrepareVisibleWebViews: schedulePrepareVisibleWebViews
            )
        )
    }
}

private func drainMainQueue() async {
    await Task.yield()
    await Task.yield()
}
