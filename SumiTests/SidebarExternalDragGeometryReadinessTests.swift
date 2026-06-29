import CoreGraphics
import XCTest

@testable import Sumi

@MainActor
final class SidebarExternalDragGeometryReadinessTests: XCTestCase {
    func testExternalDragStartFlushesDeferredGeometryBeforeFirstDropResolution() {
        let dragState = SidebarDragState()
        let spaceId = UUID()
        let location = CGPoint(x: 40, y: 170)
        let generation = dragState.activeGeometryGeneration

        dragState.schedulePageGeometry(
            spaceId: spaceId,
            profileId: nil,
            frame: CGRect(x: 0, y: 0, width: 240, height: 420),
            renderMode: .interactive,
            generation: generation
        )
        dragState.scheduleSectionFrame(
            spaceId: spaceId,
            section: .spaceRegular,
            frame: CGRect(x: 0, y: 120, width: 240, height: 240),
            generation: generation
        )
        dragState.scheduleRegularListHitTarget(
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 120, width: 240, height: 240),
            itemCount: 4,
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
