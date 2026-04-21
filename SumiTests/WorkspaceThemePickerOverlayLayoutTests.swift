import XCTest
@testable import Sumi

final class WorkspaceThemePickerOverlayLayoutTests: XCTestCase {
    func testExpandedSidebarAnchorsPickerToSidebarTrailingEdge() {
        let layout = WorkspaceThemePickerOverlayLayout(
            windowSize: CGSize(width: 1200, height: 800),
            sidebarWidth: 250,
            isSidebarVisible: true
        )

        XCTAssertEqual(layout.panelLeadingInset, 260, accuracy: 0.0001)
        XCTAssertEqual(layout.interactionFrame.origin.x, 8, accuracy: 0.0001)
        XCTAssertEqual(layout.interactionFrame.origin.y, 8, accuracy: 0.0001)
        XCTAssertEqual(layout.interactionFrame.width, 1184, accuracy: 0.0001)
        XCTAssertEqual(layout.interactionFrame.height, 784, accuracy: 0.0001)
        XCTAssertEqual(layout.scrimFrame.origin.x, 250, accuracy: 0.0001)
        XCTAssertEqual(layout.scrimFrame.origin.y, 8, accuracy: 0.0001)
        XCTAssertEqual(layout.scrimFrame.width, 942, accuracy: 0.0001)
        XCTAssertEqual(layout.scrimFrame.height, 784, accuracy: 0.0001)
        XCTAssertEqual(layout.sidebarHorizontalCenterX, 125, accuracy: 0.0001)
    }

    func testCollapsedSidebarUsesHoverOverlayInsetAsAnchor() {
        let layout = WorkspaceThemePickerOverlayLayout(
            windowSize: CGSize(width: 1200, height: 800),
            sidebarWidth: 268,
            isSidebarVisible: false
        )

        XCTAssertEqual(layout.panelLeadingInset, 285, accuracy: 0.0001)
        XCTAssertEqual(layout.scrimFrame.origin.x, 275, accuracy: 0.0001)
        XCTAssertEqual(layout.scrimFrame.width, 917, accuracy: 0.0001)
        XCTAssertEqual(layout.sidebarHorizontalCenterX, 141, accuracy: 0.0001)
    }

    func testPanelClampsInsideNarrowWindow() {
        let layout = WorkspaceThemePickerOverlayLayout(
            windowSize: CGSize(width: 420, height: 700),
            sidebarWidth: 250,
            isSidebarVisible: true
        )

        XCTAssertEqual(layout.panelLeadingInset, 32, accuracy: 0.0001)
        XCTAssertEqual(layout.scrimFrame.origin.x, 250, accuracy: 0.0001)
        XCTAssertEqual(layout.scrimFrame.width, 162, accuracy: 0.0001)
        XCTAssertEqual(layout.scrimFrame.height, 684, accuracy: 0.0001)
        XCTAssertEqual(layout.sidebarHorizontalCenterX, 125, accuracy: 0.0001)
    }
}
