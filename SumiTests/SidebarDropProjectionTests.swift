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
        let registry = SidebarTabListDragAutoscrollRegistry()
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

    func testExternalDropIndexMapsDirectly() {
        XCTAssertEqual(
            SidebarDropProjection.modelInsertionIndex(
                fromProjectedIndex: 3,
                sourceIndex: nil
            ),
            3
        )
    }

    @MainActor
    func testFavoriteProjectionRemovesDraggedSourceAndInsertsPlaceholder() {
        let spaceId = UUID()
        let profileId = UUID()
        let first = makeFavoritePin(profileId: profileId, index: 0, title: "One")
        let second = makeFavoritePin(profileId: profileId, index: 1, title: "Two")
        let third = makeFavoritePin(profileId: profileId, index: 2, title: "Three")
        let dragState = SidebarDragState()
        dragState.isDragging = true
        dragState.activeDragItemId = first.id
        dragState.activeDragScope = SidebarDragScope(
            windowId: nil,
            spaceId: spaceId,
            profileId: profileId,
            sourceContainer: .favorite,
            sourceItemId: first.id,
            sourceItemKind: .tab
        )
        dragState.presentDropResolution(
            SidebarDropResolution(
                slot: .favorite(slot: 2),
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        )

        let layout = SidebarFavoriteProjectionPolicy.make(
            items: [first, second, third].map(
                SidebarFavoriteVisualItem.pin
            ),
            width: 155,
            dragPresentation: dragState.favoritePresentation.frame
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
    func testFavoriteProjectionShowsEmptyStorePlaceholder() {
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
        dragState.presentDropResolution(
            SidebarDropResolution(
                slot: .favorite(slot: 0),
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        )

        let layout = SidebarFavoriteProjectionPolicy.make(
            items: [],
            width: 155,
            dragPresentation: dragState.favoritePresentation.frame
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
        XCTAssertEqual(
            snapshot.childOpacity(itemID: childId),
            SidebarDragSourceDim.opacity,
            accuracy: 0.0001
        )
        XCTAssertEqual(snapshot.childOpacity(itemID: otherFolderId), 1)
        XCTAssertEqual(snapshot.geometryGeneration, 42)
    }

    func testFolderDragSnapshotClearsRowChromeDuringCommit() {
        let folderId = UUID()
        let draggedId = UUID()

        let snapshot = SidebarFolderDragSnapshot(
            isCompletingDrop: true
        )

        XCTAssertFalse(snapshot.isContainTargeted(folderID: folderId))
        XCTAssertEqual(snapshot.childOpacity(itemID: draggedId), 1)
        XCTAssertEqual(snapshot.afterDropTargetHeight(rowHeight: 20), 0)
    }

    @MainActor
    func testSidebarDragGeometryMutationBufferCoalescesLatestMutationForKey() {
        let buffer = SidebarDragGeometryMutationBuffer()
        let repository = SidebarDragGeometryRepository()
        let spaceId = UUID()
        var appliedValues: [Int] = []

        buffer.enqueue(
            key: .presentedSpaceList(spaceID: spaceId, generation: 0)
        ) { _ in
            appliedValues.append(1)
        }
        buffer.enqueue(
            key: .presentedSpaceList(spaceID: spaceId, generation: 0)
        ) { _ in
            appliedValues.append(2)
        }
        buffer.enqueue(
            key: .favorite(spaceID: spaceId, generation: 0)
        ) { _ in
            appliedValues.append(3)
        }
        buffer.enqueue(
            key: .presentedSpaceList(spaceID: spaceId, generation: 1)
        ) { _ in
            appliedValues.append(4)
        }

        buffer.flush(into: repository)

        XCTAssertEqual(appliedValues.count, 3)
        XCTAssertTrue(appliedValues.contains(2))
        XCTAssertTrue(appliedValues.contains(3))
        XCTAssertTrue(appliedValues.contains(4))
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
    private func makeFavoritePin(profileId: UUID, index: Int, title: String) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: profileId,
            index: index,
            launchURL: URL(string: "https://example.com/\(index)")!,
            title: title
        )
    }
}
