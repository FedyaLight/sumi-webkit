import XCTest

@testable import Sumi

final class DockedSidebarLayoutStateTests: XCTestCase {
    func testVisibleLayoutFallsBackToFullProgressBeforeMountStateSyncs() {
        let state = DockedSidebarLayoutState()

        XCTAssertTrue(state.rendersDockedSidebar(isVisible: true))
        XCTAssertEqual(state.layoutProgress(isVisible: true), 1)
    }

    func testAnimatedHideKeepsSidebarMountedAndSeedsProgressWhenStartingCollapsed() {
        var state = DockedSidebarLayoutState()

        state.beginAnimatedHide()

        XCTAssertTrue(state.shouldRender)
        XCTAssertEqual(state.progress, 1)

        state.hide()

        XCTAssertTrue(state.shouldRender)
        XCTAssertEqual(state.progress, 0)
    }

    func testCurrentHideCompletionUnmountsOnlyWhileStillHidden() {
        var state = DockedSidebarLayoutState()
        state.beginAnimatedHide()
        state.hide()

        state.completeAnimatedHide(isVisible: false)

        XCTAssertFalse(state.shouldRender)
    }

    func testHideCompletionDoesNotUnmountAfterSidebarBecameVisible() {
        var state = DockedSidebarLayoutState()
        state.beginAnimatedHide()
        state.hide()

        state.beginShow()
        state.show()
        state.completeAnimatedHide(isVisible: true)

        XCTAssertTrue(state.shouldRender)
        XCTAssertEqual(state.progress, 1)
    }
}
