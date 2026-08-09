//
//  SidebarFavoriteDropHitFrameTests.swift
//  SumiTests
//

import XCTest

@testable import Sumi

@MainActor
final class SidebarFavoriteDropHitFrameTests: XCTestCase {
    private func makeMetrics(
        frame: CGRect,
        dropFrame: CGRect,
        dropSlotFrames: [SidebarFavoriteDropSlotMetrics],
        visibleItemCount: Int,
        itemSize: CGSize = CGSize(width: 47, height: 47),
        canAcceptDrop: Bool = true
    ) -> SidebarFavoriteLayoutMetrics {
        SidebarFavoriteLayoutMetrics(
            profileId: UUID(),
            frame: frame,
            dropFrame: dropFrame,
            dropSlotFrames: dropSlotFrames,
            firstSyntheticRowSlot: 0,
            visibleItemCount: visibleItemCount,
            visibleRowCount: max(visibleItemCount, 1),
            maxDropRowCount: 1,
            itemSize: itemSize,
            canAcceptDrop: canAcceptDrop,
            dropHitFrame: SidebarFavoriteDropHitPolicy.resolvedDropHitFrame(
                frame: frame,
                dropFrame: dropFrame,
                dropSlotFrames: dropSlotFrames,
                visibleItemCount: visibleItemCount,
                itemSize: itemSize,
                canAcceptDrop: canAcceptDrop
            )
        )
    }

    /// A collapsed empty zone has no visual height, so its hit region still
    /// widens to at least one tile for drag-and-drop.
    func testCollapsedEmptyZoneWidensItsHitFrameToOneTile() {
        let metrics = makeMetrics(
            frame: CGRect(
                x: 0,
                y: 100,
                width: 240,
                height: PinnedTileMetrics.collapsedFavoriteRevealHeight
            ),
            dropFrame: CGRect(
                x: 0,
                y: 100,
                width: 240,
                height: PinnedTileMetrics.collapsedFavoriteRevealHeight
            ),
            dropSlotFrames: [
                SidebarFavoriteDropSlotMetrics(
                    slot: 0,
                    frame: CGRect(x: 0, y: 100, width: 47, height: 47)
                ),
            ],
            visibleItemCount: 0
        )

        XCTAssertEqual(metrics.dropHitFrame.height, 47)
        XCTAssertTrue(metrics.containsDropLocation(CGPoint(x: 20, y: 130)))
    }

    /// With the placeholder on screen the reported drop frame is already the
    /// placeholder rect, so the widening union must not enlarge it further and
    /// must not reach into the pinned list below.
    func testPlaceholderSizedEmptyZoneKeepsItsReportedDropFrame() {
        let dropFrame = CGRect(
            x: 0,
            y: 100,
            width: 240,
            height: FavoritePlaceholderMetrics.height
        )
        let metrics = makeMetrics(
            frame: dropFrame,
            dropFrame: dropFrame,
            dropSlotFrames: [
                SidebarFavoriteDropSlotMetrics(slot: 0, frame: dropFrame),
            ],
            visibleItemCount: 0
        )

        XCTAssertEqual(metrics.dropHitFrame, dropFrame)
        XCTAssertTrue(metrics.containsDropLocation(CGPoint(x: 20, y: 150)))
        XCTAssertFalse(
            metrics.containsDropLocation(CGPoint(x: 20, y: dropFrame.maxY + 1))
        )
    }

    func testPopulatedZoneUsesTheReportedDropFrameVerbatim() {
        let dropFrame = CGRect(x: 0, y: 40, width: 240, height: 108)
        let metrics = makeMetrics(
            frame: CGRect(x: 0, y: 40, width: 240, height: 54),
            dropFrame: dropFrame,
            dropSlotFrames: [
                SidebarFavoriteDropSlotMetrics(
                    slot: 0,
                    frame: CGRect(x: 0, y: 400, width: 47, height: 47)
                ),
            ],
            visibleItemCount: 3
        )

        XCTAssertEqual(metrics.dropHitFrame, dropFrame)
    }

    func testFullZoneThatCannotAcceptADropIsNotWidened() {
        let dropFrame = CGRect(x: 0, y: 40, width: 240, height: 6)
        let metrics = makeMetrics(
            frame: dropFrame,
            dropFrame: dropFrame,
            dropSlotFrames: [
                SidebarFavoriteDropSlotMetrics(
                    slot: 0,
                    frame: CGRect(x: 0, y: 40, width: 47, height: 47)
                ),
            ],
            visibleItemCount: 0,
            canAcceptDrop: false
        )

        XCTAssertEqual(metrics.dropHitFrame, dropFrame)
    }
}
