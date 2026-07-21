import XCTest

@testable import Sumi

final class SidebarFolderPreviewHoverPolicyTests: XCTestCase {
    func testTimingsMatchZenPrefs() {
        // zen.folders.search.hover-delay = 500ms, mouseleave grace = 200ms.
        XCTAssertEqual(SidebarFolderPreviewHoverPolicy.showDelayNanoseconds, 500_000_000)
        XCTAssertEqual(SidebarFolderPreviewHoverPolicy.closeGraceNanoseconds, 200_000_000)
    }

    func testHoverOpensWhenNothingIsCompetingForThePointer() {
        XCTAssertTrue(
            SidebarFolderPreviewHoverPolicy.allowsOpen(
                isSidebarDragging: false,
                isHeaderPressed: false,
                isTextEntryActive: false
            )
        )
    }

    /// Zen's `movingtab` guard, extended to the press that precedes a drag so the
    /// panel never gets between the pointer and a folder being moved.
    func testDragAndPressBothSuppressOpening() {
        XCTAssertFalse(
            SidebarFolderPreviewHoverPolicy.allowsOpen(
                isSidebarDragging: true,
                isHeaderPressed: false,
                isTextEntryActive: false
            )
        )
        XCTAssertFalse(
            SidebarFolderPreviewHoverPolicy.allowsOpen(
                isSidebarDragging: false,
                isHeaderPressed: true,
                isTextEntryActive: false
            )
        )
    }

    /// Opening focuses the panel's search field, so Zen bails while the URL bar
    /// owns text entry.
    func testActiveTextEntrySuppressesOpening() {
        XCTAssertFalse(
            SidebarFolderPreviewHoverPolicy.allowsOpen(
                isSidebarDragging: false,
                isHeaderPressed: false,
                isTextEntryActive: true
            )
        )
    }

    /// Zen arms its show timer inside a real `mouseenter`, and collapsing a
    /// folder does not re-fire one. Sumi's tracking view does re-report the hover
    /// it infers from the parked pointer whenever layout or the enable flag
    /// changes — that inferred hover must not open the panel.
    func testOnlyPointerDrivenHoverArmsTheShowTimer() {
        XCTAssertTrue(SidebarFolderPreviewHoverPolicy.allowsArmingOpen(hoverSource: .pointer))
        XCTAssertFalse(SidebarFolderPreviewHoverPolicy.allowsArmingOpen(hoverSource: .lifecycle))
    }

    func testPanelStaysOpenWhileEitherSurfaceIsHovered() {
        XCTAssertTrue(
            SidebarFolderPreviewHoverPolicy.shouldStayOpen(anchorHovered: true, panelHovered: false)
        )
        XCTAssertTrue(
            SidebarFolderPreviewHoverPolicy.shouldStayOpen(anchorHovered: false, panelHovered: true)
        )
        XCTAssertFalse(
            SidebarFolderPreviewHoverPolicy.shouldStayOpen(anchorHovered: false, panelHovered: false)
        )
    }
}
