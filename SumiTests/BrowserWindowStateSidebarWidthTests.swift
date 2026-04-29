import XCTest
@testable import Sumi

final class BrowserWindowStateSidebarWidthTests: XCTestCase {
    func testSidebarWidthClampUsesMinimumWidth() {
        XCTAssertEqual(
            BrowserWindowState.clampedSidebarWidth(120),
            240,
            accuracy: 0.0001
        )
    }

    func testSidebarWidthClampUsesMaximumWidth() {
        XCTAssertEqual(
            BrowserWindowState.clampedSidebarWidth(900),
            BrowserWindowState.sidebarMaximumWidth,
            accuracy: 0.0001
        )
    }

    func testSidebarContentWidthUsesSharedPadding() {
        XCTAssertEqual(
            BrowserWindowState.sidebarContentWidth(for: BrowserWindowState.sidebarMinimumWidth),
            224,
            accuracy: 0.0001
        )
    }

    func testSidebarShellEdgeMirrorsHiddenOffsetAndResizeDelta() {
        XCTAssertEqual(
            SidebarPosition.left.shellEdge.hiddenOffset(sidebarWidth: 250, hiddenPadding: 18),
            -268,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SidebarPosition.right.shellEdge.hiddenOffset(sidebarWidth: 250, hiddenPadding: 18),
            268,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SidebarPosition.left.shellEdge.resizeDelta(startingMouseX: 100, currentMouseX: 132),
            32,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SidebarPosition.right.shellEdge.resizeDelta(startingMouseX: 100, currentMouseX: 68),
            32,
            accuracy: 0.0001
        )
    }

    func testSidebarShellEdgeUsesSideAwareResizeOffsetsAndToggleSymbols() {
        XCTAssertEqual(SidebarPosition.left.shellEdge.resizeIndicatorOffset, -3)
        XCTAssertEqual(SidebarPosition.left.shellEdge.resizeHitAreaOffset, -5)
        XCTAssertEqual(SidebarPosition.left.shellEdge.toggleSidebarSymbolName, "sidebar.left")

        XCTAssertEqual(SidebarPosition.right.shellEdge.resizeIndicatorOffset, 3)
        XCTAssertEqual(SidebarPosition.right.shellEdge.resizeHitAreaOffset, 5)
        XCTAssertEqual(SidebarPosition.right.shellEdge.toggleSidebarSymbolName, "sidebar.right")
    }

    func testSidebarShellEdgeMirrorsFallbackAnchorAndDismissRect() {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)

        XCTAssertEqual(
            SidebarPosition.left.shellEdge.sidebarBoundaryAnchorX(in: bounds, presentationWidth: 250),
            250,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SidebarPosition.right.shellEdge.sidebarBoundaryAnchorX(in: bounds, presentationWidth: 250),
            950,
            accuracy: 0.0001
        )

        let leftDismiss = SidebarPosition.left.shellEdge.sidebarDismissRect(
            in: bounds,
            presentationWidth: 250
        )
        XCTAssertEqual(leftDismiss.origin.x, 0, accuracy: 0.0001)
        XCTAssertEqual(leftDismiss.width, 250, accuracy: 0.0001)

        let rightDismiss = SidebarPosition.right.shellEdge.sidebarDismissRect(
            in: bounds,
            presentationWidth: 250
        )
        XCTAssertEqual(rightDismiss.origin.x, 950, accuracy: 0.0001)
        XCTAssertEqual(rightDismiss.width, 250, accuracy: 0.0001)
    }
}
