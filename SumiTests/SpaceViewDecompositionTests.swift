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

    func testShortcutRestoreSessionDeduplicatesOneContainerInteraction() {
        let spaceID = UUID()
        let pinID = UUID()
        let gap = ShortcutRestoreGap(
            pinId: pinID,
            container: .spacePinned(spaceID),
            index: 2
        )
        let duplicate = ShortcutRestoreGap(
            pinId: pinID,
            container: .spacePinned(spaceID),
            index: 3
        )
        var session = SpaceShortcutRestoreInteractionSession()

        XCTAssertTrue(session.register(gap))
        XCTAssertFalse(session.register(duplicate))
        XCTAssertEqual(session.gaps, [gap])

        session.appearingGapIDs.insert(gap.id)
        session.remove(gap)
        XCTAssertTrue(session.gaps.isEmpty)
        XCTAssertTrue(session.appearingGapIDs.isEmpty)
    }

    func testShortcutRestoreSessionKeepsSamePinInDistinctContainersIndependent() {
        let pinID = UUID()
        let pinnedGap = ShortcutRestoreGap(
            pinId: pinID,
            container: .spacePinned(UUID()),
            index: 0
        )
        let folderGap = ShortcutRestoreGap(
            pinId: pinID,
            container: .folder(UUID()),
            index: 0
        )
        var session = SpaceShortcutRestoreInteractionSession()

        XCTAssertTrue(session.register(pinnedGap))
        XCTAssertTrue(session.register(folderGap))
        XCTAssertEqual(session.gaps, [pinnedGap, folderGap])
    }

    func testShortcutRestorePerformRunsMatchedUpdateOnceAndRemovesOnlyMatchedGap() {
        let matchedGap = ShortcutRestoreGap(
            pinId: UUID(),
            container: .spacePinned(UUID()),
            index: 0
        )
        let retainedGap = ShortcutRestoreGap(
            pinId: UUID(),
            container: .folder(UUID()),
            index: 1
        )
        var session = SpaceShortcutRestoreInteractionSession(
            gaps: [matchedGap, retainedGap],
            appearingGapIDs: [matchedGap.id, retainedGap.id]
        )
        let binding = Binding(
            get: { session },
            set: { session = $0 }
        )
        var updateCount = 0

        SpaceShortcutRestoreInteraction.perform(
            session: binding,
            gap: matchedGap
        ) {
            updateCount += 1
        }

        XCTAssertEqual(updateCount, 1)
        XCTAssertEqual(session.gaps, [retainedGap])
        XCTAssertEqual(session.appearingGapIDs, [retainedGap.id])
    }

    func testShortcutRestorePerformRunsMissingUpdateOnceWithoutChangingSession() {
        let retainedGap = ShortcutRestoreGap(
            pinId: UUID(),
            container: .folder(UUID()),
            index: 1
        )
        let missingGap = ShortcutRestoreGap(
            pinId: UUID(),
            container: .spacePinned(UUID()),
            index: 0
        )
        var session = SpaceShortcutRestoreInteractionSession(
            gaps: [retainedGap],
            appearingGapIDs: [retainedGap.id]
        )
        let originalSession = session
        let binding = Binding(
            get: { session },
            set: { session = $0 }
        )
        var updateCount = 0

        SpaceShortcutRestoreInteraction.perform(
            session: binding,
            gap: missingGap
        ) {
            updateCount += 1
        }

        XCTAssertEqual(updateCount, 1)
        XCTAssertEqual(session, originalSession)
    }
}
