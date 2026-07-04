import Combine
import Foundation
@testable import Sumi
import XCTest

@MainActor
final class RegularTabCollectionStateOwnerTests: XCTestCase {
    func testQueriesTabsBySpaceAndIndexes() {
        let space = Space(name: "Workspace")
        let otherSpace = Space(name: "Other")
        let first = Self.makeTab(index: 0, spaceId: space.id)
        let second = Self.makeTab(index: 1, spaceId: space.id)
        let other = Self.makeTab(index: 0, spaceId: otherSpace.id)
        let owner = RegularTabCollectionStateOwner()

        owner.replaceTabsBySpace([
            space.id: [first, second],
            otherSpace.id: [other],
        ])

        XCTAssertEqual(owner.tabs(in: space).map(\.id), [first.id, second.id])
        XCTAssertEqual(owner.tabs(in: space.id).map(\.id), [first.id, second.id])
        XCTAssertEqual(owner.allTabs(in: [space]).map(\.id), [first.id, second.id])
        XCTAssertEqual(Set(owner.allTabs().map(\.id)), Set([first.id, second.id, other.id]))
        XCTAssertTrue(owner.contains(second))
        XCTAssertEqual(owner.firstIndex(of: second, in: space.id), 1)
        XCTAssertEqual(owner.appendIndex(in: space.id), 2)
        XCTAssertEqual(owner.clampedInsertionIndex(10, in: space.id), 2)
        XCTAssertEqual(owner.findSpace(for: other.id), otherSpace.id)
        XCTAssertEqual(owner.tabsBelow(first)?.map(\.id), [second.id])
        XCTAssertTrue(owner.hasTabs(in: space.id))
        XCTAssertFalse(owner.hasTabs(in: UUID()))
    }

    func testPublisherEmitsReplacementSnapshotsAndRemoveAll() {
        let spaceId = UUID()
        let tab = Self.makeTab(index: 0, spaceId: spaceId)
        let owner = RegularTabCollectionStateOwner()
        var snapshots: [[UUID]] = []
        let cancellable = owner.tabsBySpacePublisher.sink { tabsBySpace in
            snapshots.append(tabsBySpace[spaceId]?.map(\.id) ?? [])
        }

        owner.replaceTabsBySpace([spaceId: [tab]])
        owner.removeAll()

        XCTAssertEqual(snapshots, [[tab.id], []])
        cancellable.cancel()
    }

    private static func makeTab(index: Int, spaceId: UUID) -> Tab {
        Tab(
            url: URL(string: "https://example.com/\(index)")!,
            name: "Tab \(index)",
            spaceId: spaceId,
            index: index,
            loadsCachedFaviconOnInit: false
        )
    }
}

@MainActor
final class TabSelectionStateOwnerTests: XCTestCase {
    func testReplaceAndClearCurrentTabByIdentity() {
        let owner = TabSelectionStateOwner()
        let first = Self.makeTab(index: 0)
        let second = Self.makeTab(index: 1)

        owner.replaceCurrentTab(first)

        XCTAssertEqual(owner.currentTab?.id, first.id)
        XCTAssertEqual(owner.currentTabId, first.id)

        owner.clearCurrentTabIfMatches(second.id)

        XCTAssertEqual(owner.currentTab?.id, first.id)

        owner.clearCurrentTabIfMatches(first.id)

        XCTAssertNil(owner.currentTab)
        XCTAssertNil(owner.currentTabId)
    }

    private static func makeTab(index: Int) -> Tab {
        Tab(
            url: URL(string: "https://example.com/selection-\(index)")!,
            name: "Selection \(index)",
            index: index,
            loadsCachedFaviconOnInit: false
        )
    }
}
