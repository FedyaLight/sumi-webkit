import XCTest
@testable import Sumi

final class WorkspaceThemePickerPopoverPresenterTests: XCTestCase {
    @MainActor
    func testContentSizeMatchesCurrentThemePickerPanel() {
        XCTAssertEqual(
            WorkspaceThemePickerPopoverPresenter.Metrics.contentSize.width,
            GradientEditorView.panelWidth,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            WorkspaceThemePickerPopoverPresenter.Metrics.contentSize.height,
            526,
            accuracy: 0.0001
        )
    }

    func testFallbackAnchorUsesDockedSidebarTrailingEdge() {
        let rect = WorkspaceThemePickerPopoverPresenter.fallbackAnchorRect(
            in: NSRect(x: 0, y: 0, width: 1200, height: 800),
            isSidebarVisible: true,
            sidebarWidth: 250,
            savedSidebarWidth: 300
        )

        XCTAssertEqual(rect.origin.x, 250, accuracy: 0.0001)
        XCTAssertEqual(rect.origin.y, 400, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 1, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 1, accuracy: 0.0001)
    }

    func testFallbackAnchorUsesCollapsedSidebarPresentationWidth() {
        let rect = WorkspaceThemePickerPopoverPresenter.fallbackAnchorRect(
            in: NSRect(x: 0, y: 0, width: 1200, height: 800),
            isSidebarVisible: false,
            sidebarWidth: 250,
            savedSidebarWidth: 300
        )

        XCTAssertEqual(
            rect.origin.x,
            SidebarPresentationContext.collapsedSidebarWidth(
                sidebarWidth: 250,
                savedSidebarWidth: 300
            ),
            accuracy: 0.0001
        )
        XCTAssertEqual(rect.origin.y, 400, accuracy: 0.0001)
    }

    func testFallbackAnchorUsesRightSidebarInnerEdge() {
        let rect = WorkspaceThemePickerPopoverPresenter.fallbackAnchorRect(
            in: NSRect(x: 0, y: 0, width: 1200, height: 800),
            isSidebarVisible: true,
            sidebarWidth: 250,
            savedSidebarWidth: 300,
            sidebarPosition: .right
        )

        XCTAssertEqual(rect.origin.x, 950, accuracy: 0.0001)
        XCTAssertEqual(rect.origin.y, 400, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 1, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 1, accuracy: 0.0001)
    }

    func testFallbackAnchorUsesRightCollapsedSidebarPresentationWidth() {
        let rect = WorkspaceThemePickerPopoverPresenter.fallbackAnchorRect(
            in: NSRect(x: 0, y: 0, width: 1200, height: 800),
            isSidebarVisible: false,
            sidebarWidth: 250,
            savedSidebarWidth: 300,
            sidebarPosition: .right
        )

        XCTAssertEqual(
            rect.origin.x,
            1200 - SidebarPresentationContext.collapsedSidebarWidth(
                sidebarWidth: 250,
                savedSidebarWidth: 300
            ),
            accuracy: 0.0001
        )
        XCTAssertEqual(rect.origin.y, 400, accuracy: 0.0001)
    }

    func testFallbackAnchorClampsInsideNarrowWindow() {
        let rect = WorkspaceThemePickerPopoverPresenter.fallbackAnchorRect(
            in: NSRect(x: 0, y: 0, width: 120, height: 80),
            isSidebarVisible: true,
            sidebarWidth: 250,
            savedSidebarWidth: 300
        )

        XCTAssertEqual(rect.origin.x, 119, accuracy: 0.0001)
        XCTAssertEqual(rect.origin.y, 40, accuracy: 0.0001)
    }

    func testSidebarDismissRectUsesVisibleSidebarWidth() {
        let rect = WorkspaceThemePickerPopoverPresenter.sidebarDismissRect(
            in: NSRect(x: 0, y: 0, width: 1200, height: 800),
            isSidebarVisible: true,
            sidebarWidth: 250,
            savedSidebarWidth: 300
        )

        XCTAssertEqual(rect.origin.x, 0, accuracy: 0.0001)
        XCTAssertEqual(rect.origin.y, 0, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 250, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 800, accuracy: 0.0001)
    }

    func testSidebarDismissRectUsesCollapsedSidebarWidthAndClamps() {
        let rect = WorkspaceThemePickerPopoverPresenter.sidebarDismissRect(
            in: NSRect(x: 0, y: 0, width: 120, height: 80),
            isSidebarVisible: false,
            sidebarWidth: 250,
            savedSidebarWidth: 300
        )

        XCTAssertEqual(rect.origin.x, 0, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 120, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 80, accuracy: 0.0001)
    }

    func testSidebarDismissRectUsesRightSidebarWidth() {
        let rect = WorkspaceThemePickerPopoverPresenter.sidebarDismissRect(
            in: NSRect(x: 0, y: 0, width: 1200, height: 800),
            isSidebarVisible: true,
            sidebarWidth: 250,
            savedSidebarWidth: 300,
            sidebarPosition: .right
        )

        XCTAssertEqual(rect.origin.x, 950, accuracy: 0.0001)
        XCTAssertEqual(rect.origin.y, 0, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 250, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 800, accuracy: 0.0001)
    }

    func testSidebarDismissRectUsesRightCollapsedSidebarWidthAndClamps() {
        let rect = WorkspaceThemePickerPopoverPresenter.sidebarDismissRect(
            in: NSRect(x: 0, y: 0, width: 120, height: 80),
            isSidebarVisible: false,
            sidebarWidth: 250,
            savedSidebarWidth: 300,
            sidebarPosition: .right
        )

        XCTAssertEqual(rect.origin.x, 0, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 120, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 80, accuracy: 0.0001)
    }
}
