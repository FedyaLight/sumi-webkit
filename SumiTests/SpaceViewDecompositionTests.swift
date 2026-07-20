import SwiftUI
import XCTest

@testable import Sumi

@MainActor
final class SpaceViewDecompositionTests: XCTestCase {
    func testInteractiveRenderModeFailsClosedWhenSidebarInteractiveWorkIsDisabled() {
        XCTAssertTrue(
            SpaceViewRenderMode.interactive.resolvesInteraction(allowsInteraction: true)
        )
        XCTAssertFalse(
            SpaceViewRenderMode.interactive.resolvesInteraction(allowsInteraction: false)
        )
        XCTAssertFalse(
            SpaceViewRenderMode.transitionSnapshot.resolvesInteraction(allowsInteraction: true)
        )
    }

    private func dragSnapshot(
        active: Bool = false,
        source: TabDragManager.DragContainer? = nil,
        itemID: UUID? = nil,
        hoveredSlot: DropZoneSlot? = nil,
        externalGap: SidebarRegularExternalDropGap? = nil,
        completing: Bool = false,
        hidesCommittedPlaceholder: Bool = false
    ) -> SpaceRegularTabsListProjection.DragSnapshot {
        .init(
            isDropProjectionActive: active,
            sourceContainer: source,
            dragItemID: itemID,
            hoveredSlot: hoveredSlot,
            externalDropGap: externalGap,
            isCompletingDrop: completing,
            hidesCommittedCrossContainerPlaceholder: hidesCommittedPlaceholder
        )
    }

    func testRegularProjectionUsesAnimationFallbackOutsideDragSession() {
        let spaceID = UUID()
        let tabID = UUID()
        let fallbackGapID = UUID()
        let projection = SpaceRegularTabsListProjection(
            spaceID: spaceID,
            tabIDs: [tabID],
            showsBottomNewTabButton: false,
            drag: dragSnapshot()
        )

        XCTAssertFalse(projection.usesProjectedDropLayout)
        XCTAssertEqual(
            projection.displayItems(fallback: [.gap(fallbackGapID)]),
            [.gap(fallbackGapID)]
        )
    }

    func testRegularProjectionReordersWithinItsOwnContainer() {
        let spaceID = UUID()
        let firstID = UUID()
        let draggedID = UUID()
        let projection = SpaceRegularTabsListProjection(
            spaceID: spaceID,
            tabIDs: [firstID, draggedID],
            showsBottomNewTabButton: false,
            drag: dragSnapshot(
                active: true,
                source: .spaceRegular(spaceID),
                itemID: draggedID,
                hoveredSlot: .spaceRegular(spaceId: spaceID, slot: 0)
            )
        )

        XCTAssertEqual(projection.sourceID, draggedID)
        XCTAssertEqual(projection.insertionIndex, 0)
        XCTAssertEqual(projection.projectedItems, [.placeholder, .item(firstID)])
    }

    func testRegularProjectionKeepsSameContainerCommitProjection() {
        let spaceID = UUID()
        let firstID = UUID()
        let draggedID = UUID()
        let projection = SpaceRegularTabsListProjection(
            spaceID: spaceID,
            tabIDs: [firstID, draggedID],
            showsBottomNewTabButton: false,
            drag: dragSnapshot(
                active: true,
                source: .spaceRegular(spaceID),
                itemID: draggedID,
                hoveredSlot: .spaceRegular(spaceId: spaceID, slot: 0),
                completing: true
            )
        )

        XCTAssertEqual(projection.sourceID, draggedID)
        XCTAssertEqual(projection.insertionIndex, 0)
        XCTAssertEqual(projection.projectedItems, [.placeholder, .item(firstID)])
    }

    func testRegularProjectionSuppressesCommitGapFromShortcutContainer() {
        let spaceID = UUID()
        let projection = SpaceRegularTabsListProjection(
            spaceID: spaceID,
            tabIDs: [],
            showsBottomNewTabButton: false,
            drag: dragSnapshot(
                active: true,
                source: .spacePinned(UUID()),
                itemID: UUID(),
                hoveredSlot: .spaceRegular(spaceId: spaceID, slot: 0),
                completing: true
            )
        )

        XCTAssertNil(projection.insertionIndex)
        XCTAssertFalse(projection.usesProjectedDropLayout)
    }

    func testRegularProjectionKeepsExternalBottomGapBehindVisibleNewTabRow() {
        let spaceID = UUID()
        let gap = SidebarRegularExternalDropGap(spaceId: spaceID, edge: .bottom)

        XCTAssertNil(
            SpaceRegularTabsListProjection(
                spaceID: spaceID,
                tabIDs: [],
                showsBottomNewTabButton: false,
                drag: dragSnapshot(externalGap: gap)
            ).externalDropGapPlacement
        )
        XCTAssertEqual(
            SpaceRegularTabsListProjection(
                spaceID: spaceID,
                tabIDs: [],
                showsBottomNewTabButton: true,
                drag: dragSnapshot(externalGap: gap)
            ).externalDropGapPlacement,
            .bottom
        )
    }

    func testRegularProjectionAlwaysPlacesExternalTopGap() {
        let spaceID = UUID()
        let gap = SidebarRegularExternalDropGap(spaceId: spaceID, edge: .top)
        let projection = SpaceRegularTabsListProjection(
            spaceID: spaceID,
            tabIDs: [],
            showsBottomNewTabButton: false,
            drag: dragSnapshot(externalGap: gap)
        )

        XCTAssertEqual(projection.externalDropGapPlacement, .top)
        XCTAssertNil(projection.insertionIndex)
    }

    func testRegularProjectionIgnoresExternalGapForAnotherSpace() {
        let spaceID = UUID()
        let tabID = UUID()
        let projection = SpaceRegularTabsListProjection(
            spaceID: spaceID,
            tabIDs: [tabID],
            showsBottomNewTabButton: true,
            drag: dragSnapshot(
                active: true,
                source: .spacePinned(UUID()),
                itemID: UUID(),
                hoveredSlot: .spaceRegular(spaceId: spaceID, slot: 1),
                externalGap: SidebarRegularExternalDropGap(
                    spaceId: UUID(),
                    edge: .top
                )
            )
        )

        XCTAssertNil(projection.externalDropGapPlacement)
        XCTAssertEqual(projection.insertionIndex, 1)
        XCTAssertEqual(projection.projectedItems, [.item(tabID), .placeholder])
    }

    func testRegularProjectionHidesResolvedCrossContainerCommitPlaceholder() {
        let spaceID = UUID()
        let draggedID = UUID()
        let projection = SpaceRegularTabsListProjection(
            spaceID: spaceID,
            tabIDs: [draggedID],
            showsBottomNewTabButton: false,
            drag: dragSnapshot(
                active: true,
                source: .spacePinned(UUID()),
                itemID: draggedID,
                hoveredSlot: .spaceRegular(spaceId: spaceID, slot: 0),
                completing: true,
                hidesCommittedPlaceholder: true
            )
        )

        XCTAssertNil(projection.sourceID)
        XCTAssertNil(projection.insertionIndex)
        XCTAssertFalse(projection.usesProjectedDropLayout)
    }

    func testRegularProjectionUsesStableDragIdentityForProjectedGap() {
        let spaceID = UUID()
        let draggedID = UUID()
        let projection = SpaceRegularTabsListProjection(
            spaceID: spaceID,
            tabIDs: [],
            showsBottomNewTabButton: false,
            drag: dragSnapshot(
                active: true,
                source: .spacePinned(UUID()),
                itemID: draggedID,
                hoveredSlot: .spaceRegular(spaceId: spaceID, slot: 0)
            )
        )

        XCTAssertEqual(
            projection.displayItems(fallback: []),
            [.gap(regularDragProjectionGapID)]
        )
    }

}
