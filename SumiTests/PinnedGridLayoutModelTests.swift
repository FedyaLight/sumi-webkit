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
            role: .essential,
            index: index,
            launchURL: URL(string: "https://example.com/\(index)")!,
            title: "Pin \(index)"
        )
    }

    private func makeModel(
        width: CGFloat = 300,
        items: [ShortcutPin] = [],
        dragState: SidebarDragState = SidebarDragState(),
        animateLayout: Bool = true,
        reportsGeometry: Bool = true,
        isActiveWindow: Bool = true,
        isTransitioningProfile: Bool = false,
        shouldReduceMotion: Bool = false
    ) -> PinnedGridLayoutModel {
        PinnedGridLayoutModel(
            width: width,
            items: items,
            dragState: dragState,
            geometrySpaceId: UUID(),
            effectiveProfileId: UUID(),
            animateLayout: animateLayout,
            reportsGeometry: reportsGeometry,
            isActiveWindow: isActiveWindow,
            isTransitioningProfile: isTransitioningProfile,
            shouldReduceMotion: shouldReduceMotion
        )
    }

    // MARK: - Empty essentials

    func testEmptyItemsWithoutHoverCollapsesToMinimalRevealHeight() {
        let model = makeModel(items: [])

        XCTAssertFalse(model.showsRevealGap)
        XCTAssertEqual(model.revealHeight, 6)
        XCTAssertEqual(model.maxDropRowCount, 1)
        XCTAssertEqual(model.dropFrame, CGRect(x: 0, y: 0, width: 300, height: 6))
    }

    // MARK: - Non-empty essentials

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

        let expected = SidebarEssentialsProjectionPolicy.neededRowCountAfterDrop(
            itemIDs: items.map(\.id),
            visibleItemCount: model.projectedLayout.visibleItemCount,
            layoutItemCount: model.projectedLayout.projectedItemCount,
            columnCount: model.projectedLayout.columnCount,
            canAcceptDrop: model.projectedLayout.canAcceptDrop,
            dragState: SidebarDragState()
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

        // No active drag: SidebarDragState.shouldAnimateDropLayout requires isDragging.
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
