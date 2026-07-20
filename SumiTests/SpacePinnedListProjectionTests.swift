//
//  SpacePinnedListProjectionTests.swift
//  SumiTests
//

import XCTest

@testable import Sumi

@MainActor
final class SpacePinnedListProjectionTests: XCTestCase {
    private func makeSnapshot(
        isDropProjectionActive: Bool = false,
        sourceContainer: TabDragManager.DragContainer? = nil,
        dragItemId: UUID? = nil,
        hoveredSpaceId: UUID? = nil,
        hoveredSlot: Int? = nil,
        folderDropIntent: FolderDropIntent = .none,
        hidesPlaceholder: Bool = false
    ) -> SpacePinnedListProjection.DragProjectionSnapshot {
        .init(
            isDropProjectionActive: isDropProjectionActive,
            sourceContainer: sourceContainer,
            dragItemId: dragItemId,
            hoveredSpaceId: hoveredSpaceId,
            hoveredSlot: hoveredSlot,
            folderDropIntent: folderDropIntent,
            hidesCommittedCrossContainerPlaceholder: hidesPlaceholder
        )
    }

    // MARK: - projectedInsertionIndex

    func testProjectedInsertionIndexNilWhenProjectionInactive() {
        let spaceId = UUID()
        let model = SpacePinnedListProjection(
            spaceId: spaceId,
            items: [],
            dragProjection: makeSnapshot(isDropProjectionActive: false, hoveredSpaceId: spaceId, hoveredSlot: 0)
        )

        XCTAssertNil(model.projectedInsertionIndex)
    }

    func testProjectedInsertionIndexNilForDifferentSpace() {
        let spaceId = UUID()
        let model = SpacePinnedListProjection(
            spaceId: spaceId,
            items: [],
            dragProjection: makeSnapshot(isDropProjectionActive: true, hoveredSpaceId: UUID(), hoveredSlot: 0)
        )

        XCTAssertNil(model.projectedInsertionIndex)
    }

    func testProjectedInsertionIndexNilWhenFolderDropIntentIsActive() {
        let spaceId = UUID()
        let model = SpacePinnedListProjection(
            spaceId: spaceId,
            items: [],
            dragProjection: makeSnapshot(
                isDropProjectionActive: true,
                hoveredSpaceId: spaceId,
                hoveredSlot: 1,
                folderDropIntent: .contain(folderId: UUID())
            )
        )

        XCTAssertNil(model.projectedInsertionIndex)
    }

    func testProjectedInsertionIndexReturnsSlotWhenActive() {
        let spaceId = UUID()
        let model = SpacePinnedListProjection(
            spaceId: spaceId,
            items: [],
            dragProjection: makeSnapshot(isDropProjectionActive: true, hoveredSpaceId: spaceId, hoveredSlot: 2)
        )

        XCTAssertEqual(model.projectedInsertionIndex, 2)
    }

    func testProjectedInsertionIndexNilWhenCrossContainerPlaceholderShouldHide() {
        let spaceId = UUID()
        let dragItemId = UUID()
        let model = SpacePinnedListProjection(
            spaceId: spaceId,
            items: [.shortcut(dragItemId)],
            dragProjection: makeSnapshot(
                isDropProjectionActive: true,
                dragItemId: dragItemId,
                hoveredSpaceId: spaceId,
                hoveredSlot: 0,
                hidesPlaceholder: true
            )
        )

        XCTAssertNil(model.projectedInsertionIndex)
    }

    // MARK: - projectedSourceItem

    func testProjectedSourceItemResolvesDraggedItemFromSameContainer() {
        let spaceId = UUID()
        let dragItemId = UUID()
        let model = SpacePinnedListProjection(
            spaceId: spaceId,
            items: [.shortcut(dragItemId), .folder(UUID())],
            dragProjection: makeSnapshot(
                isDropProjectionActive: true,
                sourceContainer: .spacePinned(spaceId),
                dragItemId: dragItemId
            )
        )

        XCTAssertEqual(model.projectedSourceItem, .shortcut(dragItemId))
    }

    func testProjectedSourceItemNilForDifferentSourceContainer() {
        let spaceId = UUID()
        let dragItemId = UUID()
        let model = SpacePinnedListProjection(
            spaceId: spaceId,
            items: [.shortcut(dragItemId)],
            dragProjection: makeSnapshot(
                isDropProjectionActive: true,
                sourceContainer: .essentials,
                dragItemId: dragItemId
            )
        )

        XCTAssertNil(model.projectedSourceItem)
    }

    // MARK: - displayEntries

    func testDisplayEntriesAssignDropIndexOnlyToRealItems() {
        let spaceId = UUID()
        let folderIdA = UUID()
        let folderIdB = UUID()
        let dragItemId = UUID()
        let model = SpacePinnedListProjection(
            spaceId: spaceId,
            items: [.folder(folderIdA), .folder(folderIdB)],
            dragProjection: makeSnapshot(
                isDropProjectionActive: true,
                dragItemId: dragItemId,
                hoveredSpaceId: spaceId,
                hoveredSlot: 1
            )
        )

        let entries = model.displayEntries
        XCTAssertEqual(entries.map(\.item), [.item(.folder(folderIdA)), .dragPlaceholder, .item(.folder(folderIdB))])
        XCTAssertEqual(entries.map(\.dropIndex), [0, 1, 1])
    }

    func testDisplayIDUsesDragItemIdForPlaceholder() {
        let spaceId = UUID()
        let dragItemId = UUID()
        let model = SpacePinnedListProjection(
            spaceId: spaceId,
            items: [],
            dragProjection: makeSnapshot(dragItemId: dragItemId)
        )

        XCTAssertEqual(model.displayID(for: .dragPlaceholder, placeholderIndex: 3), "item-\(dragItemId.uuidString)")
    }

    func testDisplayIDFallsBackToPlaceholderIndexWithoutDragItemId() {
        let spaceId = UUID()
        let model = SpacePinnedListProjection(
            spaceId: spaceId,
            items: [],
            dragProjection: makeSnapshot()
        )

        XCTAssertEqual(model.displayID(for: .dragPlaceholder, placeholderIndex: 3), "placeholder-3")
    }
}
