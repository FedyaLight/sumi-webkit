import XCTest

@testable import Sumi

@MainActor
final class SwipeWindowMutationFlushOwnerTests: XCTestCase {
    func testFlushOwnerPreparesVisibleWebViewsBeforeRefreshingCompositor() {
        let owner = HistorySwipeWindowMutationFlushOwner()
        let windowState = BrowserWindowState()
        var events: [String] = []

        owner.enqueue(.prepareVisibleWebViews, for: windowState)
        owner.flushPendingMutations(
            in: windowState.id,
            prepareVisibleWebViews: { preparedWindowState in
                XCTAssertIdentical(preparedWindowState, windowState)
                events.append("prepare")
                return true
            },
            refreshCompositor: { refreshedWindowState in
                XCTAssertIdentical(refreshedWindowState, windowState)
                events.append("refresh")
            }
        )

        XCTAssertEqual(events, ["prepare", "refresh"])
    }

    func testFlushOwnerRefreshesWithoutPreparingForRefreshOnlyMutation() {
        let owner = HistorySwipeWindowMutationFlushOwner()
        let windowState = BrowserWindowState()
        var events: [String] = []

        owner.enqueue(.refreshCompositor, for: windowState)
        owner.flushPendingMutations(
            in: windowState.id,
            prepareVisibleWebViews: { _ in
                events.append("prepare")
                return true
            },
            refreshCompositor: { refreshedWindowState in
                XCTAssertIdentical(refreshedWindowState, windowState)
                events.append("refresh")
            }
        )

        XCTAssertEqual(events, ["refresh"])
    }
}
