//
//  PinnedGridLayoutModelTests.swift
//  SumiTests
//

import XCTest

@testable import Sumi

@MainActor
final class PinnedGridLayoutModelTests: XCTestCase {
    private func makePin(index: Int) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .favorite,
            index: index,
            launchURL: URL(string: "https://example.com/\(index)")!,
            title: "Pin \(index)"
        )
    }

    private func makeModel(
        width: CGFloat = 300,
        items: [ShortcutPin] = [],
        dragState: SidebarDragState = SidebarDragState(),
        showsHint: Bool = false,
        animateLayout: Bool = true,
        reportsGeometry: Bool = true,
        isActiveWindow: Bool = true,
        isTransitioningProfile: Bool = false,
        shouldReduceMotion: Bool = false
    ) -> PinnedGridLayoutModel {
        PinnedGridLayoutModel(
            width: width,
            items: items.map(SidebarFavoriteVisualItem.pin),
            dragPresentation: dragState.favoritePresentation.frame,
            dragGeometry: dragState.geometry,
            geometrySpaceId: UUID(),
            effectiveProfileId: UUID(),
            showsHint: showsHint,
            animateLayout: animateLayout,
            reportsGeometry: reportsGeometry,
            isActiveWindow: isActiveWindow,
            isTransitioningProfile: isTransitioningProfile,
            shouldReduceMotion: shouldReduceMotion
        )
    }

    /// Puts the favorite presentation into the state the resolver produces
    /// while a drag hovers an empty zone.
    private func makeHoveringDragState() -> SidebarDragState {
        let dragState = SidebarDragState()
        dragState.beginExternalDragSession(itemId: nil)
        dragState.presentDropResolution(
            SidebarDropResolution(
                slot: .favorite(slot: 0),
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        )
        return dragState
    }

    // MARK: - Empty favorite

    func testEmptyItemsWithoutHintOrHoverHaveNoVisualRevealHeight() {
        let model = makeModel(items: [], showsHint: false)

        XCTAssertEqual(model.emptyPresentation, .collapsed)
        XCTAssertEqual(model.revealHeight, 0)
        XCTAssertEqual(model.maxDropRowCount, 1)
        XCTAssertEqual(
            model.dropFrame,
            CGRect(
                x: 0,
                y: 0,
                width: 300,
                height: 0
            )
        )
    }

    func testUndismissedHintShowsThePlaceholderWithoutADrag() {
        let model = makeModel(items: [], showsHint: true)

        XCTAssertEqual(model.emptyPresentation, .placeholder)
        XCTAssertEqual(model.revealHeight, FavoritePlaceholderMetrics.height)
        XCTAssertEqual(
            model.dropFrame,
            CGRect(x: 0, y: 0, width: 300, height: FavoritePlaceholderMetrics.height)
        )
    }

    func testDismissedHintRevealsThePlaceholderWhileADragHoversTheZone() {
        let model = makeModel(
            items: [],
            dragState: makeHoveringDragState(),
            showsHint: false
        )

        XCTAssertEqual(model.emptyPresentation, .placeholder)
        XCTAssertEqual(model.revealHeight, FavoritePlaceholderMetrics.height)
    }

    func testDragHoveringAnotherZoneLeavesTheEmptyFavoriteCollapsed() {
        let dragState = SidebarDragState()
        dragState.beginExternalDragSession(itemId: nil)
        dragState.presentDropResolution(
            SidebarDropResolution(
                slot: .spaceRegular(spaceId: UUID(), slot: 0),
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        )

        let model = makeModel(items: [], dragState: dragState, showsHint: false)

        XCTAssertEqual(model.emptyPresentation, .collapsed)
    }

    func testNonEmptyFavoriteNeverReportAnEmptyPresentation() {
        let model = makeModel(items: [makePin(index: 0)], showsHint: true)

        XCTAssertEqual(model.emptyPresentation, .collapsed)
    }

    // MARK: - Non-empty favorite

    func testNonEmptyItemsProduceDisplayRowsMatchingItemCount() {
        let items = (0..<3).map(makePin)
        let model = makeModel(width: 300, items: items)

        XCTAssertEqual(model.projectedLayout.visibleItemCount, 3)
        XCTAssertFalse(model.displayRows.isEmpty)
        XCTAssertGreaterThanOrEqual(model.visibleRowCount, 1)
    }

    func testMaxDropRowCountMatchesPolicyComputation() {
        let items = (0..<3).map(makePin)
        let model = makeModel(width: 300, items: items)

        let expected = SidebarFavoriteProjectionPolicy.neededRowCountAfterDrop(
            itemIDs: items.map(\.id),
            visibleItemCount: model.projectedLayout.visibleItemCount,
            layoutItemCount: model.projectedLayout.projectedItemCount,
            columnCount: model.projectedLayout.columnCount,
            canAcceptDrop: model.projectedLayout.canAcceptDrop,
            dragPresentation: SidebarFavoriteDragPresentationFrame()
        )

        XCTAssertEqual(model.maxDropRowCount, expected)
    }

    // MARK: - Animation gating

    func testAnimationsDisabledWhenAnimateLayoutIsFalse() {
        let dragState = SidebarDragState()
        dragState.beginExternalDragSession(itemId: nil)
        let model = makeModel(dragState: dragState, animateLayout: false)

        XCTAssertFalse(model.shouldAnimateDropLayout)
        XCTAssertFalse(model.shouldAnimateContentLayout)
    }

    func testAnimationsDisabledWhenWindowIsNotActive() {
        let dragState = SidebarDragState()
        dragState.beginExternalDragSession(itemId: nil)
        let model = makeModel(dragState: dragState, isActiveWindow: false)

        XCTAssertFalse(model.shouldAnimateDropLayout)
        XCTAssertFalse(model.shouldAnimateContentLayout)
    }

    func testAnimationsDisabledWhenReduceMotionRequested() {
        let dragState = SidebarDragState()
        dragState.beginExternalDragSession(itemId: nil)
        let model = makeModel(dragState: dragState, shouldReduceMotion: true)

        XCTAssertFalse(model.shouldAnimateDropLayout)
        XCTAssertFalse(model.shouldAnimateContentLayout)
    }

    func testContentLayoutAnimatesWithoutAnActiveDragButDropLayoutDoesNot() {
        let model = makeModel(dragState: SidebarDragState())

        // No active drag: the presentation frame does not animate drop layout.
        XCTAssertFalse(model.shouldAnimateDropLayout)
        XCTAssertTrue(model.shouldAnimateContentLayout)
    }

    func testDropLayoutAnimatesWhileDraggingAndAllConditionsAllow() {
        let dragState = SidebarDragState()
        dragState.beginExternalDragSession(itemId: nil)
        let model = makeModel(dragState: dragState)

        XCTAssertTrue(model.shouldAnimateDropLayout)
        XCTAssertTrue(model.shouldAnimateContentLayout)
    }

    // MARK: - Detailed geometry reporting

    func testReportsDetailedGeometryFalseWhenReportsGeometryDisabled() {
        let dragState = SidebarDragState()
        dragState.beginExternalDragSession(itemId: nil)
        let model = makeModel(dragState: dragState, reportsGeometry: false)

        XCTAssertFalse(model.reportsDetailedGeometry)
    }

    func testReportsDetailedGeometryFalseWithoutActiveDrag() {
        let model = makeModel(dragState: SidebarDragState(), reportsGeometry: true)

        XCTAssertFalse(model.reportsDetailedGeometry)
    }

    func testReportsDetailedGeometryTrueDuringExternalDragSession() {
        let dragState = SidebarDragState()
        dragState.beginExternalDragSession(itemId: nil)
        let model = makeModel(dragState: dragState, reportsGeometry: true)

        XCTAssertTrue(model.reportsDetailedGeometry)
    }
}
