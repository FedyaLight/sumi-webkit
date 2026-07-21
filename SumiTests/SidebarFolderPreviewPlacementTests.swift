import XCTest

@testable import Sumi

@MainActor
final class SidebarFolderPreviewPlacementTests: XCTestCase {
    private let containerBounds = CGRect(x: 0, y: 0, width: 1_400, height: 900)

    /// Zen: `position: "topright topleft"`, `x: 10`, `y: -(min(rows, 6) * 48) / 2`.
    func testLeftSidebarPlacesPanelOutwardAndLiftedByHalfTheList() {
        let anchor = CGRect(x: 20, y: 400, width: 240, height: 36)

        let frame = SidebarFolderPreviewPlacement.frame(
            anchorRect: anchor,
            candidateCount: 4,
            sidebarPosition: .left,
            containerBounds: containerBounds
        )

        XCTAssertEqual(frame.minX, anchor.maxX + SidebarFolderPreviewPlacement.anchorGap)
        XCTAssertEqual(frame.minY, anchor.minY - (4 * SidebarFolderPreviewMetrics.rowSlotHeight) / 2)
        XCTAssertEqual(frame.width, SidebarFolderPreviewMetrics.width)
    }

    func testRightSidebarMirrorsPlacementToTheLeadingSide() {
        let anchor = CGRect(x: 1_140, y: 400, width: 240, height: 36)

        let frame = SidebarFolderPreviewPlacement.frame(
            anchorRect: anchor,
            candidateCount: 4,
            sidebarPosition: .right,
            containerBounds: containerBounds
        )

        XCTAssertEqual(
            frame.maxX,
            anchor.minX - SidebarFolderPreviewPlacement.anchorGap
        )
    }

    /// Zen caps the lift at six slots even though the list scrolls further.
    func testLiftIsCappedAtSixRowSlots() {
        let anchor = CGRect(x: 20, y: 600, width: 240, height: 36)

        let capped = SidebarFolderPreviewPlacement.frame(
            anchorRect: anchor,
            candidateCount: 20,
            sidebarPosition: .left,
            containerBounds: containerBounds
        )
        let atCap = SidebarFolderPreviewPlacement.frame(
            anchorRect: anchor,
            candidateCount: 6,
            sidebarPosition: .left,
            containerBounds: containerBounds
        )

        XCTAssertEqual(capped.minY, atCap.minY)
        XCTAssertEqual(
            capped.minY,
            anchor.minY - (6 * SidebarFolderPreviewMetrics.rowSlotHeight) / 2
        )
    }

    /// Firefox's widget layer keeps a panel on screen; an in-window overlay has
    /// to clamp itself or a folder near the top would render half outside.
    func testPanelIsClampedInsideTheContainer() {
        let topAnchor = CGRect(x: 20, y: 8, width: 240, height: 36)

        let frame = SidebarFolderPreviewPlacement.frame(
            anchorRect: topAnchor,
            candidateCount: 6,
            sidebarPosition: .left,
            containerBounds: containerBounds
        )

        XCTAssertEqual(
            frame.minY,
            containerBounds.minY + SidebarFolderPreviewPlacement.containerMargin
        )
        XCTAssertLessThanOrEqual(
            frame.maxY,
            containerBounds.maxY - SidebarFolderPreviewPlacement.containerMargin
        )
    }

    func testBottomAnchorIsPulledUpToFitTheContainer() {
        let bottomAnchor = CGRect(x: 20, y: 870, width: 240, height: 36)

        let frame = SidebarFolderPreviewPlacement.frame(
            anchorRect: bottomAnchor,
            candidateCount: 6,
            sidebarPosition: .left,
            containerBounds: containerBounds
        )

        XCTAssertEqual(
            frame.maxY,
            containerBounds.maxY - SidebarFolderPreviewPlacement.containerMargin
        )
    }

    /// A container narrower/shorter than the panel would invert the clamp range.
    func testUndersizedContainerPinsToLeadingEdgeInsteadOfInverting() {
        let tinyContainer = CGRect(x: 0, y: 0, width: 120, height: 120)

        let frame = SidebarFolderPreviewPlacement.frame(
            anchorRect: CGRect(x: 0, y: 40, width: 60, height: 36),
            candidateCount: 3,
            sidebarPosition: .left,
            containerBounds: tinyContainer
        )

        XCTAssertEqual(frame.minX, SidebarFolderPreviewPlacement.containerMargin)
        XCTAssertEqual(frame.minY, SidebarFolderPreviewPlacement.containerMargin)
    }

    func testPanelHeightGrowsWithRowSlotsAndStopsAtZenMaxListHeight() {
        let chromeHeight = SidebarFolderPreviewMetrics.searchHeaderHeight
            + SidebarFolderPreviewMetrics.separatorHeight

        XCTAssertEqual(
            SidebarFolderPreviewMetrics.panelHeight(candidateCount: 3),
            chromeHeight + 3 * SidebarFolderPreviewMetrics.rowSlotHeight
        )
        XCTAssertEqual(
            SidebarFolderPreviewMetrics.panelHeight(candidateCount: 40),
            chromeHeight + SidebarFolderPreviewMetrics.maxListHeight
        )
    }
}
