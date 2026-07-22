import CoreGraphics
import XCTest

@testable import Sumi

@MainActor
final class ExternalDragGeometryReadinessTests: XCTestCase {
    func testUniformPinnedListResolvesFromOneListMetric() {
        let dragState = SidebarDragState()
        let spaceId = UUID()
        let generation = dragState.geometry.activeGeometryGeneration

        dragState.geometry.report(
            .page(
                spaceId: spaceId,
                profileId: nil,
                frame: CGRect(x: 0, y: 0, width: 240, height: 420),
                renderMode: .interactive
            ),
            generation: generation
        )
        dragState.geometry.report(
            .section(
                spaceId: spaceId,
                section: .spacePinned,
                frame: CGRect(x: 0, y: 80, width: 240, height: 134)
            ),
            generation: generation
        )
        dragState.geometry.report(
            .pinnedList(
                spaceId: spaceId,
                frame: CGRect(x: 0, y: 80, width: 240, height: 134),
                rowCount: 3,
                leadingInset: 18
            ),
            generation: generation
        )

        dragState.beginExternalDragSession(itemId: nil)
        let resolution = SidebarDropResolver.resolve(
            location: CGPoint(x: 40, y: 145),
            state: dragState,
            draggedItem: nil
        )

        XCTAssertEqual(resolution.slot, .spacePinned(spaceId: spaceId, slot: 1))
    }

    func testExternalDragStartFlushesDeferredGeometryBeforeFirstDropResolution() {
        let dragState = SidebarDragState()
        let spaceId = UUID()
        let location = CGPoint(x: 40, y: 170)
        let generation = dragState.geometry.activeGeometryGeneration

        dragState.geometry.report(
            .page(
                spaceId: spaceId,
                profileId: nil,
                frame: CGRect(x: 0, y: 0, width: 240, height: 420),
                renderMode: .interactive
            ),
            generation: generation
        )
        dragState.geometry.report(
            .section(
                spaceId: spaceId,
                section: .spaceRegular,
                frame: CGRect(x: 0, y: 120, width: 240, height: 240)
            ),
            generation: generation
        )
        dragState.geometry.report(
            .regularList(
                spaceId: spaceId,
                frame: CGRect(x: 0, y: 120, width: 240, height: 240),
                rowIdentities: (0..<4).map { _ in .tab(UUID()) }
            ),
            generation: generation
        )

        dragState.beginExternalDragSession(itemId: nil)
        let resolution = SidebarDropResolver.updateState(
            location: location,
            state: dragState,
            draggedItem: nil
        )

        XCTAssertEqual(resolution.slot, .spaceRegular(spaceId: spaceId, slot: 1))
        XCTAssertEqual(dragState.hoveredSlot, .spaceRegular(spaceId: spaceId, slot: 1))
    }
}
