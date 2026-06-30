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

        let generation = state.beginAnimatedHide()

        XCTAssertEqual(generation, 1)
        XCTAssertTrue(state.shouldRender)
        XCTAssertEqual(state.progress, 1)

        state.hide()

        XCTAssertTrue(state.shouldRender)
        XCTAssertEqual(state.progress, 0)
    }

    func testCurrentHideCompletionUnmountsOnlyWhileStillHidden() {
        var state = DockedSidebarLayoutState()
        let generation = state.beginAnimatedHide()
        state.hide()

        state.completeAnimatedHide(generation: generation, isVisible: false)

        XCTAssertFalse(state.shouldRender)
    }

    func testStaleHideCompletionDoesNotUnmountAfterShow() {
        var state = DockedSidebarLayoutState()
        let staleGeneration = state.beginAnimatedHide()
        state.hide()

        state.beginShow()
        state.show()
        state.completeAnimatedHide(generation: staleGeneration, isVisible: true)

        XCTAssertTrue(state.shouldRender)
        XCTAssertEqual(state.progress, 1)
    }
}
