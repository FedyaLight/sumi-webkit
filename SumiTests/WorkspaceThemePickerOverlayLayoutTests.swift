import XCTest
@testable import Sumi

final class WorkspaceThemePickerOverlayLayoutTests: XCTestCase {
    func testExpandedSidebarAnchorsPickerToSidebarTrailingEdge() {
        let layout = WorkspaceThemePickerOverlayLayout(
            windowSize: CGSize(width: 1200, height: 800),
            sidebarWidth: 250
        )

        XCTAssertEqual(layout.panelLeadingInset, 260, accuracy: 0.0001)
        XCTAssertEqual(layout.interactionFrame.origin.x, 8, accuracy: 0.0001)
        XCTAssertEqual(layout.interactionFrame.origin.y, 8, accuracy: 0.0001)
        XCTAssertEqual(layout.interactionFrame.width, 1184, accuracy: 0.0001)
        XCTAssertEqual(layout.interactionFrame.height, 784, accuracy: 0.0001)
        XCTAssertEqual(layout.sidebarHorizontalCenterX, 125, accuracy: 0.0001)
    }

    func testCollapsedSidebarAnchorsToSharedSidebarEdge() {
        let layout = WorkspaceThemePickerOverlayLayout(
            windowSize: CGSize(width: 1200, height: 800),
            sidebarWidth: 268
        )

        XCTAssertEqual(layout.panelLeadingInset, 278, accuracy: 0.0001)
        XCTAssertEqual(layout.sidebarHorizontalCenterX, 134, accuracy: 0.0001)
    }

    func testPanelClampsInsideNarrowWindow() {
        let layout = WorkspaceThemePickerOverlayLayout(
            windowSize: CGSize(width: 420, height: 700),
            sidebarWidth: 250
        )

        XCTAssertEqual(layout.panelLeadingInset, 32, accuracy: 0.0001)
        XCTAssertEqual(layout.sidebarHorizontalCenterX, 125, accuracy: 0.0001)
    }
}
