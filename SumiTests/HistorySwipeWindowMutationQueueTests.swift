import XCTest

@testable import Sumi

@MainActor
final class HistorySwipeWindowMutationQueueTests: XCTestCase {
    func testTakePendingMutationsCoalescesKindsAndRemovesRecord() {
        var queue = HistorySwipeWindowMutationQueue()
        let windowState = BrowserWindowState()

        queue.enqueue(.refreshCompositor, for: windowState)
        queue.enqueue(.prepareVisibleWebViews, for: windowState)

        let pendingMutations = queue.takePendingMutations(for: windowState.id)

        XCTAssertEqual(pendingMutations?.needsVisibleWebViewPreparation, true)
        XCTAssertEqual(pendingMutations?.needsCompositorRefresh, true)
        XCTAssertIdentical(pendingMutations?.windowState, windowState)
        XCTAssertNil(queue.takePendingMutations(for: windowState.id))
    }

    func testPrepareOnlyMutationRequiresVisibleWebViewPreparationAndCompositorRefresh() {
        var queue = HistorySwipeWindowMutationQueue()
        let windowState = BrowserWindowState()

        queue.enqueue(.prepareVisibleWebViews, for: windowState)

        let pendingMutations = queue.takePendingMutations(for: windowState.id)

        XCTAssertEqual(pendingMutations?.needsVisibleWebViewPreparation, true)
        XCTAssertEqual(pendingMutations?.needsCompositorRefresh, true)
    }

    func testRefreshOnlyMutationDoesNotRequireVisibleWebViewPreparation() {
        var queue = HistorySwipeWindowMutationQueue()
        let windowState = BrowserWindowState()

        queue.enqueue(.refreshCompositor, for: windowState)

        let pendingMutations = queue.takePendingMutations(for: windowState.id)

        XCTAssertEqual(pendingMutations?.needsCompositorRefresh, true)
        XCTAssertEqual(pendingMutations?.needsVisibleWebViewPreparation, false)
    }

    func testCancelRemovesPendingRecord() {
        var queue = HistorySwipeWindowMutationQueue()
        let windowState = BrowserWindowState()

        queue.enqueue(.prepareVisibleWebViews, for: windowState)
        queue.cancel(in: windowState.id)

        XCTAssertNil(queue.takePendingMutations(for: windowState.id))
    }

    func testTakePendingMutationsDropsRecordWhenWindowStateWasReleased() {
        var queue = HistorySwipeWindowMutationQueue()
        var windowState: BrowserWindowState? = BrowserWindowState()
        let windowId = windowState!.id

        queue.enqueue(.refreshCompositor, for: windowState!)
        windowState = nil

        XCTAssertNil(queue.takePendingMutations(for: windowId))
        XCTAssertNil(queue.takePendingMutations(for: windowId))
    }
}
