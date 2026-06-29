import AppKit
import CoreGraphics
import Foundation
import XCTest

@testable import Sumi

final class SidebarDropProjectionTests: XCTestCase {
    func testTabListAutoscrollPolicyActivatesOnlyInsideVerticalEdgeBands() {
        let viewport = CGRect(x: 10, y: 100, width: 240, height: 320)

        XCTAssertEqual(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.midX, y: viewport.maxY - 4),
                in: viewport
            ),
            .up
        )
        XCTAssertEqual(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.midX, y: viewport.minY + 4),
                in: viewport
            ),
            .down
        )
        XCTAssertNil(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.midX, y: viewport.midY),
                in: viewport
            )
        )
        XCTAssertNil(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.maxX + 1, y: viewport.minY + 4),
                in: viewport
            )
        )
    }

    func testTabListAutoscrollPolicyKeepsShortViewportsBoundedToNearestEdge() {
        let viewport = CGRect(x: 0, y: 0, width: 80, height: 40)

        XCTAssertEqual(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.midX, y: viewport.maxY - 2),
                in: viewport
            ),
            .up
        )
        XCTAssertEqual(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.midX, y: viewport.minY + 2),
                in: viewport
            ),
            .down
        )
        XCTAssertNil(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.midX, y: viewport.midY),
                in: viewport
            )
        )
    }

    func testTabListAutoscrollPolicyStepIncreasesTowardEdge() {
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 300)
        let nearEdgeStep = SidebarTabListAutoscrollPolicy.step(
            for: CGPoint(x: viewport.midX, y: viewport.minY + 2),
            in: viewport,
            direction: .down
        )
        let fartherFromEdgeStep = SidebarTabListAutoscrollPolicy.step(
            for: CGPoint(x: viewport.midX, y: viewport.minY + 24),
            in: viewport,
            direction: .down
        )

        XCTAssertGreaterThan(nearEdgeStep, fartherFromEdgeStep)
        XCTAssertGreaterThanOrEqual(fartherFromEdgeStep, SidebarTabListAutoscrollPolicy.minimumStep)
        XCTAssertLessThanOrEqual(nearEdgeStep, SidebarTabListAutoscrollPolicy.maximumStep)
    }

    @MainActor
    func testRegisteredScrollViewPrefersSmallestViewportContainingPoint() {
        let registry = SidebarTabListDragAutoscrollRegistry.shared
        registry.stop()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let rootView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = rootView

        let largeScrollView = makeScrollView(frame: NSRect(x: 20, y: 20, width: 260, height: 260))
        let smallScrollView = makeScrollView(frame: NSRect(x: 80, y: 80, width: 90, height: 90))

        rootView.addSubview(largeScrollView)
        rootView.addSubview(smallScrollView)
        registry.register(largeScrollView)
        registry.register(smallScrollView)

        defer {
            registry.unregister(largeScrollView)
            registry.unregister(smallScrollView)
            registry.stop()
            window.contentView = nil
            window.close()
        }

        let smallViewport = smallScrollView.contentView.convert(smallScrollView.contentView.bounds, to: nil)
        let largeViewport = largeScrollView.contentView.convert(largeScrollView.contentView.bounds, to: nil)
        let overlappingPoint = CGPoint(x: smallViewport.midX, y: smallViewport.midY)

        XCTAssertTrue(largeViewport.contains(overlappingPoint))
        XCTAssertTrue(smallViewport.contains(overlappingPoint))
        XCTAssertTrue(
            registry.registeredScrollView(
                containingWindowPoint: overlappingPoint,
                in: window
            ) === smallScrollView
        )
    }

    func testProjectedIndexBeforeSourceMapsDirectlyToModelIndex() {
        XCTAssertEqual(
            SidebarDropProjection.modelInsertionIndex(
                fromProjectedIndex: 0,
                sourceIndex: 2
            ),
            0
        )
        XCTAssertEqual(
            SidebarDropProjection.modelInsertionIndex(
                fromProjectedIndex: 2,
                sourceIndex: 2
            ),
            2
        )
    }

    func testProjectedIndexAfterSourceMapsPastRemovedSourceInModelIndex() {
        XCTAssertEqual(
            SidebarDropProjection.modelInsertionIndex(
                fromProjectedIndex: 2,
                sourceIndex: 0
            ),
            3
        )
        XCTAssertEqual(
            SidebarDropProjection.modelInsertionIndex(
                fromProjectedIndex: 3,
                sourceIndex: 1
            ),
            4
        )
    }

    func testModelIndexConvertsBackToProjectedIndex() {
        for sourceIndex in 0..<4 {
            for projectedIndex in 0...4 {
                let modelIndex = SidebarDropProjection.modelInsertionIndex(
                    fromProjectedIndex: projectedIndex,
                    sourceIndex: sourceIndex
                )
                XCTAssertEqual(
                    SidebarDropProjection.projectedInsertionIndex(
                        fromModelIndex: modelIndex,
                        sourceIndex: sourceIndex
                    ),
                    projectedIndex,
                    "sourceIndex=\(sourceIndex) projectedIndex=\(projectedIndex) modelIndex=\(modelIndex)"
                )
            }
        }
    }

    func testExternalDropIndexMapsDirectly() {
        XCTAssertEqual(
            SidebarDropProjection.modelInsertionIndex(
                fromProjectedIndex: 3,
                sourceIndex: nil
            ),
            3
        )
        XCTAssertEqual(
            SidebarDropProjection.projectedInsertionIndex(
                fromModelIndex: 3,
                sourceIndex: nil
            ),
            3
        )
    }

    func testProjectedItemsRemoveSourceAndInsertPlaceholder() {
        XCTAssertEqual(
            SidebarDropProjection.projectedItems(
                itemIDs: ["A", "B", "C"],
                sourceID: "A",
                projectedInsertionIndex: 2
            ),
            [.item("B"), .item("C"), .placeholder]
        )
        XCTAssertEqual(
            SidebarDropProjection.projectedItems(
                itemIDs: ["A", "B", "C"],
                sourceID: "B",
                projectedInsertionIndex: 0
            ),
            [.placeholder, .item("A"), .item("C")]
        )
    }

    func testProjectedItemsWithoutPlaceholderOnlyRemoveSource() {
        XCTAssertEqual(
            SidebarDropProjection.projectedItems(
                itemIDs: ["A", "B", "C"],
                sourceID: "B",
                projectedInsertionIndex: nil
            ),
            [.item("A"), .item("C")]
        )
    }

    func testProjectedItemsClampPlaceholderSlot() {
        XCTAssertEqual(
            SidebarDropProjection.projectedItems(
                itemIDs: ["A", "B", "C"],
                sourceID: "C",
                projectedInsertionIndex: 99
            ),
            [.item("A"), .item("B"), .placeholder]
        )
    }

    @MainActor
    func testEssentialsProjectionRemovesDraggedSourceAndInsertsPlaceholder() {
        let spaceId = UUID()
        let profileId = UUID()
        let first = makeEssentialPin(profileId: profileId, index: 0, title: "One")
        let second = makeEssentialPin(profileId: profileId, index: 1, title: "Two")
        let third = makeEssentialPin(profileId: profileId, index: 2, title: "Three")
        let dragState = SidebarDragState()
        dragState.isDragging = true
        dragState.activeDragItemId = first.id
        dragState.activeDragScope = SidebarDragScope(
            windowId: nil,
            spaceId: spaceId,
            profileId: profileId,
            sourceContainer: .essentials,
            sourceItemId: first.id,
            sourceItemKind: .tab
        )
        dragState.hoveredSlot = .essentials(slot: 2)

        let layout = SidebarEssentialsProjectionPolicy.make(
            items: [first, second, third],
            width: 155,
            configuration: .large,
            dragState: dragState
        )

        XCTAssertEqual(layout.visibleItems.compactMap { $0?.id }, [second.id, third.id])
        XCTAssertEqual(layout.layoutItems.count, 3)
        XCTAssertEqual(layout.layoutItems[0]?.id, second.id)
        XCTAssertEqual(layout.layoutItems[1]?.id, third.id)
        XCTAssertNil(layout.layoutItems[2])
        XCTAssertEqual(layout.capacityColumnCount, 3)
        XCTAssertEqual(layout.visualColumnSignature, [3])
    }

    @MainActor
    func testEssentialsProjectionShowsEmptyStorePlaceholder() {
        let draggedId = UUID()
        let dragState = SidebarDragState()
        dragState.isDragging = true
        dragState.activeDragItemId = draggedId
        dragState.activeDragScope = SidebarDragScope(
            windowId: nil,
            spaceId: UUID(),
            profileId: UUID(),
            sourceContainer: .spaceRegular(UUID()),
            sourceItemId: draggedId,
            sourceItemKind: .tab
        )
        dragState.hoveredSlot = .essentials(slot: 0)

        let layout = SidebarEssentialsProjectionPolicy.make(
            items: [],
            width: 155,
            configuration: .large,
            dragState: dragState
        )

        XCTAssertTrue(layout.canAcceptDrop)
        XCTAssertTrue(layout.visibleItems.isEmpty)
        XCTAssertEqual(layout.layoutItems.count, 1)
        XCTAssertNil(layout.layoutItems[0])
        XCTAssertEqual(layout.projectedItemCount, 1)
        XCTAssertEqual(layout.visibleRowCount, 0)
        XCTAssertEqual(layout.rows.first?.startSlot, 0)
        XCTAssertEqual(layout.rows.first?.visualColumnCount, 1)
    }

    func testFolderProjectionRemovesDraggedSourceAndInsertsPlaceholderInOpenFolder() {
        let folderId = UUID()
        let draggedFolderId = UUID()
        let shortcutId = UUID()
        let splitGroupId = UUID()

        let items = SidebarFolderDisplayProjection.renderedItems(
            baseItems: [
                .folder(draggedFolderId),
                .shortcut(shortcutId),
                .splitGroup(splitGroupId),
            ],
            folderID: folderId,
            isFolderOpen: true,
            restoreGaps: [],
            dragProjection: SidebarFolderDragDisplayProjection(
                isActive: true,
                sourceFolderID: folderId,
                draggedItemID: draggedFolderId,
                folderDropIntent: .insertIntoFolder(folderId: folderId, index: 2),
                suppressesCommittedPlaceholder: false
            )
        )

        XCTAssertEqual(items, [.shortcut(shortcutId), .splitGroup(splitGroupId), .placeholder])
    }

    func testFolderProjectionDoesNotInsertPlaceholderIntoClosedFolder() {
        let folderId = UUID()
        let draggedShortcutId = UUID()
        let shortcutId = UUID()

        let items = SidebarFolderDisplayProjection.renderedItems(
            baseItems: [.shortcut(draggedShortcutId), .shortcut(shortcutId)],
            folderID: folderId,
            isFolderOpen: false,
            restoreGaps: [],
            dragProjection: SidebarFolderDragDisplayProjection(
                isActive: true,
                sourceFolderID: folderId,
                draggedItemID: draggedShortcutId,
                folderDropIntent: .insertIntoFolder(folderId: folderId, index: 1),
                suppressesCommittedPlaceholder: false
            )
        )

        XCTAssertEqual(items, [.shortcut(shortcutId)])
    }

    func testFolderProjectionSuppressesCommittedPlaceholderForRegularSource() {
        let folderId = UUID()
        let draggedTabId = UUID()
        let shortcutId = UUID()

        let items = SidebarFolderDisplayProjection.renderedItems(
            baseItems: [.shortcut(shortcutId)],
            folderID: folderId,
            isFolderOpen: true,
            restoreGaps: [],
            dragProjection: SidebarFolderDragDisplayProjection(
                isActive: true,
                sourceFolderID: nil,
                draggedItemID: draggedTabId,
                folderDropIntent: .insertIntoFolder(folderId: folderId, index: 0),
                suppressesCommittedPlaceholder: true
            )
        )

        XCTAssertEqual(items, [.shortcut(shortcutId)])
    }

    func testFolderProjectionKeepsSameFolderCommitPlaceholder() {
        let folderId = UUID()
        let draggedShortcutId = UUID()
        let shortcutId = UUID()

        let items = SidebarFolderDisplayProjection.renderedItems(
            baseItems: [.shortcut(draggedShortcutId), .shortcut(shortcutId)],
            folderID: folderId,
            isFolderOpen: true,
            restoreGaps: [],
            dragProjection: SidebarFolderDragDisplayProjection(
                isActive: true,
                sourceFolderID: folderId,
                draggedItemID: draggedShortcutId,
                folderDropIntent: .insertIntoFolder(folderId: folderId, index: 1),
                suppressesCommittedPlaceholder: false
            )
        )

        XCTAssertEqual(items, [.shortcut(shortcutId), .placeholder])
    }

    func testFolderProjectionMergesShortcutRestoreGapAfterDragProjection() {
        let folderId = UUID()
        let draggedShortcutId = UUID()
        let restoredShortcutId = UUID()
        let gap = ShortcutRestoreGap(
            pinId: restoredShortcutId,
            container: .folder(folderId),
            index: 0
        )

        let items = SidebarFolderDisplayProjection.renderedItems(
            baseItems: [.shortcut(draggedShortcutId), .shortcut(restoredShortcutId)],
            folderID: folderId,
            isFolderOpen: true,
            restoreGaps: [gap],
            dragProjection: SidebarFolderDragDisplayProjection(
                isActive: true,
                sourceFolderID: folderId,
                draggedItemID: draggedShortcutId,
                folderDropIntent: .insertIntoFolder(folderId: folderId, index: 1),
                suppressesCommittedPlaceholder: false
            )
        )

        XCTAssertEqual(items, [.restoreGap(gap.id), .placeholder])
    }

    func testFolderDisplayEntriesDoNotAdvanceDropIndexForPlaceholderOrRestoreGap() {
        let shortcutId = UUID()
        let draggedShortcutId = UUID()
        let restoredShortcutId = UUID()
        let childFolderId = UUID()
        let gap = ShortcutRestoreGap(
            pinId: restoredShortcutId,
            container: .folder(UUID()),
            index: 0
        )

        let entries = SidebarFolderDisplayProjection.displayEntries(
            from: [
                .shortcut(shortcutId),
                .placeholder,
                .restoreGap(gap.id),
                .folder(childFolderId),
            ],
            restoreGaps: [gap],
            placeholderDragItemID: draggedShortcutId
        )

        XCTAssertEqual(entries.map(\.dropIndex), [0, 1, 1, 1])
        XCTAssertEqual(entries.map(\.id), [
            "item-\(shortcutId.uuidString)",
            "item-\(draggedShortcutId.uuidString)",
            "item-\(restoredShortcutId.uuidString)",
            "folder-\(childFolderId.uuidString)",
        ])
    }

    func testFolderDragSnapshotDerivesFolderPresentationState() {
        let folderId = UUID()
        let otherFolderId = UUID()
        let childId = UUID()

        let snapshot = SidebarFolderDragSnapshot(
            isDragging: true,
            activeDragItemID: childId,
            activeHoveredFolderID: folderId,
            folderDropIntent: .contain(folderId: folderId),
            geometryGeneration: 42
        )

        XCTAssertTrue(snapshot.isContainTargeted(folderID: folderId))
        XCTAssertFalse(snapshot.isContainTargeted(folderID: otherFolderId))
        XCTAssertTrue(snapshot.isFolderPreviewOpen(folderID: folderId, isOpen: false))
        XCTAssertFalse(snapshot.isFolderPreviewOpen(folderID: otherFolderId, isOpen: false))
        XCTAssertTrue(snapshot.isFolderPreviewOpen(folderID: otherFolderId, isOpen: true))
        XCTAssertEqual(snapshot.afterDropTargetHeight(rowHeight: 20), 9)
        XCTAssertEqual(snapshot.childOpacity(itemID: childId), 0.001, accuracy: 0.0001)
        XCTAssertEqual(snapshot.childOpacity(itemID: otherFolderId), 1)
        XCTAssertTrue(snapshot.allowsLayoutAnimation(isInteractive: true))
        XCTAssertFalse(snapshot.allowsLayoutAnimation(isInteractive: false))
        XCTAssertEqual(snapshot.geometryGeneration, 42)
    }

    func testFolderDragSnapshotKeepsCompletionProjectionSeparateFromLiveHover() {
        let folderId = UUID()
        let draggedId = UUID()

        let snapshot = SidebarFolderDragSnapshot(
            isCompletingDrop: true,
            projectionDragItemID: draggedId,
            projectionSourceContainer: .folder(folderId),
            projectionFolderDropIntent: .insertIntoFolder(folderId: folderId, index: 1)
        )

        XCTAssertTrue(snapshot.isDropProjectionActive)
        XCTAssertEqual(snapshot.projectionSourceFolderID, folderId)
        XCTAssertEqual(snapshot.projectionDragItemID, draggedId)
        XCTAssertEqual(
            snapshot.projectionFolderDropIntent,
            .insertIntoFolder(folderId: folderId, index: 1)
        )
        XCTAssertFalse(snapshot.isContainTargeted(folderID: folderId))
        XCTAssertEqual(snapshot.childOpacity(itemID: draggedId), 1)
        XCTAssertFalse(snapshot.allowsLayoutAnimation(isInteractive: true))
    }

    func testFolderDragSnapshotUsesCommittedPlaceholderPolicy() {
        let sourceSpaceId = UUID()
        let sourceFolderId = UUID()
        let targetFolderId = UUID()

        let regularSourceCommit = SidebarFolderDragSnapshot(
            isCompletingDrop: true,
            projectionSourceContainer: .spaceRegular(sourceSpaceId)
        )

        XCTAssertTrue(
            regularSourceCommit.shouldHideCommittedPlaceholder(
                into: .folder(targetFolderId),
                targetAlreadyContainsDraggedItem: false
            )
        )

        let sameFolderCommit = SidebarFolderDragSnapshot(
            isCompletingDrop: true,
            projectionSourceContainer: .folder(sourceFolderId)
        )

        XCTAssertFalse(
            sameFolderCommit.shouldHideCommittedPlaceholder(
                into: .folder(sourceFolderId),
                targetAlreadyContainsDraggedItem: true
            )
        )
        XCTAssertTrue(
            sameFolderCommit.shouldHideCommittedPlaceholder(
                into: .folder(targetFolderId),
                targetAlreadyContainsDraggedItem: true
            )
        )
        XCTAssertFalse(
            sameFolderCommit.shouldHideCommittedPlaceholder(
                into: .folder(targetFolderId),
                targetAlreadyContainsDraggedItem: false
            )
        )

        let activeDrag = SidebarFolderDragSnapshot(
            isDragging: true,
            projectionSourceContainer: .folder(sourceFolderId)
        )

        XCTAssertFalse(
            activeDrag.shouldHideCommittedPlaceholder(
                into: .folder(targetFolderId),
                targetAlreadyContainsDraggedItem: true
            )
        )
    }

    @MainActor
    func testSidebarDragGeometryMutationBufferCoalescesLatestMutationForKey() {
        let buffer = SidebarDragGeometryMutationBuffer()
        let repository = SidebarDragGeometryRepository()
        let spaceId = UUID()
        var appliedValues: [Int] = []

        buffer.enqueue(key: .regularList(spaceId)) { _ in
            appliedValues.append(1)
        }
        buffer.enqueue(key: .regularList(spaceId)) { _ in
            appliedValues.append(2)
        }
        buffer.enqueue(
            key: .section(SidebarSectionGeometryKey(spaceId: spaceId, section: .spacePinned))
        ) { _ in
            appliedValues.append(3)
        }

        buffer.flush(into: repository)

        XCTAssertEqual(appliedValues.count, 2)
        XCTAssertTrue(appliedValues.contains(2))
        XCTAssertTrue(appliedValues.contains(3))
        XCTAssertFalse(appliedValues.contains(1))
    }

    @MainActor
    private func makeScrollView(frame: NSRect) -> NSScrollView {
        let scrollView = NSScrollView(frame: frame)
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.documentView = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: frame.width,
                height: frame.height
            )
        )
        return scrollView
    }

    @MainActor
    private func makeEssentialPin(profileId: UUID, index: Int, title: String) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            index: index,
            launchURL: URL(string: "https://example.com/\(index)")!,
            title: title
        )
    }
}
