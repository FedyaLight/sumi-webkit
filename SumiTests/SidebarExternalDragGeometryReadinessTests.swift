import CoreGraphics
import SumiDomain
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
            .presentedSpaceList(
                presentedLayout(
                    spaceID: spaceId,
                    pinnedList: SidebarPinnedListHitMetrics(
                        frame: CGRect(x: 0, y: 80, width: 240, height: 134),
                        rowCount: 3,
                        splitPairingMemberIDsByRow: Array(
                            repeating: [],
                            count: 3
                        ),
                        leadingInset: 18
                    )
                )
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

    func testUniformPinnedListResolvesPairingWithoutPerRowGeometry() throws {
        let dragState = SidebarDragState()
        let spaceId = UUID()
        let targetPinID = UUID()
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
            .presentedSpaceList(
                presentedLayout(
                    spaceID: spaceId,
                    pinnedList: SidebarPinnedListHitMetrics(
                        frame: CGRect(x: 0, y: 80, width: 240, height: 134),
                        rowCount: 3,
                        splitPairingMemberIDsByRow: [
                            [.shortcutPin(targetPinID)],
                            [.shortcutPin(UUID())],
                            [.shortcutPin(UUID())],
                        ],
                        leadingInset: 18
                    )
                )
            ),
            generation: generation
        )

        dragState.beginExternalDragSession(itemId: nil)
        let resolution = SidebarDropResolver.resolve(
            location: CGPoint(x: 190, y: 116),
            state: dragState,
            draggedItem: SumiDragItem(
                tabId: UUID(),
                title: "Dragged"
            )
        )

        XCTAssertEqual(
            resolution.slot,
            .spacePinned(spaceId: spaceId, slot: 1)
        )
        XCTAssertEqual(
            try XCTUnwrap(resolution.splitPairingTarget).memberID,
            .shortcutPin(targetPinID)
        )
        XCTAssertEqual(resolution.splitPairingTarget?.side, .right)
    }

    func testPairingPresentationWaitsForDwellWhileInsertionStaysImmediate() throws {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let dragState = SidebarDragState(
            delayedActions: delayedActions.scheduler
        )
        let spaceId = UUID()
        let targetPinID = UUID()
        let generation = dragState.geometry.activeGeometryGeneration
        let location = CGPoint(x: 190, y: 116)
        let draggedItem = SumiDragItem(tabId: UUID(), title: "Dragged")

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
            .presentedSpaceList(
                presentedLayout(
                    spaceID: spaceId,
                    pinnedList: SidebarPinnedListHitMetrics(
                        frame: CGRect(x: 0, y: 80, width: 240, height: 134),
                        rowCount: 3,
                        splitPairingMemberIDsByRow: [
                            [.shortcutPin(targetPinID)],
                            [.shortcutPin(UUID())],
                            [.shortcutPin(UUID())],
                        ],
                        leadingInset: 18
                    )
                )
            ),
            generation: generation
        )
        dragState.beginExternalDragSession(itemId: nil)

        let insertion = SidebarDropResolver.updateState(
            location: location,
            state: dragState,
            draggedItem: draggedItem
        )

        XCTAssertEqual(
            insertion.slot,
            .spacePinned(spaceId: spaceId, slot: 1)
        )
        XCTAssertNil(insertion.splitPairingTarget)
        XCTAssertNotNil(insertion.indicatorLineRect)
        XCTAssertEqual(delayedActions.pendingActionCount, 1)

        delayedActions.runNext()

        let pairing = SidebarDropResolver.updateState(
            location: location,
            state: dragState,
            draggedItem: draggedItem
        )

        XCTAssertEqual(
            try XCTUnwrap(pairing.splitPairingTarget).memberID,
            .shortcutPin(targetPinID)
        )
        XCTAssertNil(pairing.indicatorLineRect)
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
            .presentedSpaceList(
                presentedLayout(
                    spaceID: spaceId,
                    regularList: SidebarRegularListHitMetrics(
                        frame: CGRect(x: 0, y: 120, width: 240, height: 240),
                        rowIdentities: (0..<4).map { _ in .tab(UUID()) }
                    )
                )
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

private func presentedLayout(
    spaceID: UUID,
    pinnedList: SidebarPinnedListHitMetrics? = nil,
    regularList: SidebarRegularListHitMetrics? = nil
) -> PresentedSidebarLayout {
    let pinnedFrame = pinnedList?.frame
        ?? CGRect(x: 0, y: 80, width: 240, height: 40)
    let regular = regularList
        ?? SidebarRegularListHitMetrics(
            frame: CGRect(x: 0, y: pinnedFrame.maxY, width: 240, height: 0),
            rowIdentities: []
        )
    return PresentedSidebarLayout(
        spaceID: spaceID,
        sectionFrames: [
            .spacePinned: pinnedFrame,
            .spaceRegular: regular.frame,
        ],
        topLevelPinnedItemTargets: [:],
        folderDropTargets: [:],
        folderChildDropTargets: [:],
        pinnedListHitTarget: pinnedList,
        regularListHitTarget: regular
    )
}
