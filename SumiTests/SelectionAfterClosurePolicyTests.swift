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
            favoriteTabs: [],
            spacePinnedTabs: [pinned],
            regularTabs: [first, second],
            removedIndexInCurrentSpace: 2
        )

        let next = selectedTab(from: snapshot)

        XCTAssertEqual(next?.id, second.id)
    }

    func testRemovedIndexFallsBackToFavoriteTabsWhenSpaceBecomesEmpty() {
        let favorite = makeTab(url: "https://favorite.example", spaceId: nil)
        let snapshot = SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: false,
            hasCurrentSpace: true,
            favoriteTabs: [favorite],
            spacePinnedTabs: [],
            regularTabs: [],
            removedIndexInCurrentSpace: 0
        )

        let next = selectedTab(from: snapshot)

        XCTAssertEqual(next?.id, favorite.id)
    }

    func testEmptySpaceWithoutIndexFallsBackThroughRegularPinnedFavorite() {
        let favorite = makeTab(url: "https://favorite.example", spaceId: nil)
        let pinned = makeTab(url: "https://pinned.example", spaceId: UUID())
        let snapshot = SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: false,
            hasCurrentSpace: true,
            favoriteTabs: [favorite],
            spacePinnedTabs: [pinned],
            regularTabs: [],
            removedIndexInCurrentSpace: nil
        )

        let next = selectedTab(from: snapshot)

        XCTAssertEqual(next?.id, pinned.id)
    }

    func testClosingGlobalPinnedUsesOneCoherentFavoriteThenSpaceFallback() {
        let favoriteA = makeTab(url: "https://a.example", spaceId: nil)
        let favoriteB = makeTab(url: "https://b.example", spaceId: nil)
        let spacePinned = makeTab(url: "https://space.example", spaceId: UUID())
        let regular = makeTab(url: "https://regular.example", spaceId: spacePinned.spaceId)

        let withFavorite = SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: true,
            hasCurrentSpace: true,
            favoriteTabs: [favoriteA, favoriteB],
            spacePinnedTabs: [spacePinned],
            regularTabs: [regular],
            removedIndexInCurrentSpace: nil
        )
        XCTAssertEqual(
            selectedTab(from: withFavorite)?.id,
            favoriteB.id
        )

        let withoutFavorite = SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: true,
            hasCurrentSpace: true,
            favoriteTabs: [],
            spacePinnedTabs: [spacePinned],
            regularTabs: [regular],
            removedIndexInCurrentSpace: nil
        )
        XCTAssertEqual(
            selectedTab(from: withoutFavorite)?.id,
            spacePinned.id
        )
    }

    func testSpaceTabWithoutCurrentSpacePreservesExistingSelectionSemantics() {
        let snapshot = SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: false,
            hasCurrentSpace: false,
            favoriteTabs: [makeTab(url: "https://favorite.example", spaceId: nil)],
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
