import XCTest

@testable import Sumi

@MainActor
final class SelectionAfterClosurePolicyTests: XCTestCase {
    func testRemovedIndexSelectsClampedNeighborInSpaceOrdering() {
        let pinned = makeTab(url: "https://pinned.example", spaceId: UUID())
        let first = makeTab(url: "https://first.example", spaceId: pinned.spaceId)
        let second = makeTab(url: "https://second.example", spaceId: pinned.spaceId)
        let snapshot = SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: false,
            hasCurrentSpace: true,
            essentialTabs: [],
            spacePinnedTabs: [pinned],
            regularTabs: [first, second],
            removedIndexInCurrentSpace: 2
        )

        let next = selectedTab(from: snapshot)

        XCTAssertEqual(next?.id, second.id)
    }

    func testRemovedIndexFallsBackToEssentialTabsWhenSpaceBecomesEmpty() {
        let essential = makeTab(url: "https://essential.example", spaceId: nil)
        let snapshot = SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: false,
            hasCurrentSpace: true,
            essentialTabs: [essential],
            spacePinnedTabs: [],
            regularTabs: [],
            removedIndexInCurrentSpace: 0
        )

        let next = selectedTab(from: snapshot)

        XCTAssertEqual(next?.id, essential.id)
    }

    func testEmptySpaceWithoutIndexFallsBackThroughRegularPinnedEssential() {
        let essential = makeTab(url: "https://essential.example", spaceId: nil)
        let pinned = makeTab(url: "https://pinned.example", spaceId: UUID())
        let snapshot = SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: false,
            hasCurrentSpace: true,
            essentialTabs: [essential],
            spacePinnedTabs: [pinned],
            regularTabs: [],
            removedIndexInCurrentSpace: nil
        )

        let next = selectedTab(from: snapshot)

        XCTAssertEqual(next?.id, pinned.id)
    }

    func testClosingGlobalPinnedUsesOneCoherentEssentialThenSpaceFallback() {
        let essentialA = makeTab(url: "https://a.example", spaceId: nil)
        let essentialB = makeTab(url: "https://b.example", spaceId: nil)
        let spacePinned = makeTab(url: "https://space.example", spaceId: UUID())
        let regular = makeTab(url: "https://regular.example", spaceId: spacePinned.spaceId)

        let withEssentials = SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: true,
            hasCurrentSpace: true,
            essentialTabs: [essentialA, essentialB],
            spacePinnedTabs: [spacePinned],
            regularTabs: [regular],
            removedIndexInCurrentSpace: nil
        )
        XCTAssertEqual(
            selectedTab(from: withEssentials)?.id,
            essentialB.id
        )

        let withoutEssentials = SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: true,
            hasCurrentSpace: true,
            essentialTabs: [],
            spacePinnedTabs: [spacePinned],
            regularTabs: [regular],
            removedIndexInCurrentSpace: nil
        )
        XCTAssertEqual(
            selectedTab(from: withoutEssentials)?.id,
            spacePinned.id
        )
    }

    func testSpaceTabWithoutCurrentSpacePreservesExistingSelectionSemantics() {
        let snapshot = SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: false,
            hasCurrentSpace: false,
            essentialTabs: [makeTab(url: "https://essential.example", spaceId: nil)],
            spacePinnedTabs: [],
            regularTabs: [],
            removedIndexInCurrentSpace: 0
        )

        guard case .keepCurrent = SelectionAfterClosurePolicy.decision(
            from: snapshot
        ) else {
            return XCTFail("Expected the existing selection to remain unchanged")
        }
    }

    private func makeTab(url: String, spaceId: UUID?) -> Tab {
        Tab(
            url: URL(string: url)!,
            spaceId: spaceId,
            index: 0,
            loadsCachedFaviconOnInit: false
        )
    }

    private func selectedTab(
        from snapshot: SelectionAfterClosurePolicy.Snapshot
    ) -> Tab? {
        guard case .replaceCurrent(let tab) =
            SelectionAfterClosurePolicy.decision(from: snapshot)
        else {
            XCTFail("Expected a replacement selection")
            return nil
        }
        return tab
    }
}
