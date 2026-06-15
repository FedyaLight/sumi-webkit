import XCTest

@testable import Sumi

@MainActor
final class TabLazyRestoreCoordinatorTests: XCTestCase {
    func testPlannerPrefersNearestAdjacentTabsAroundAnchor() {
        let spaceId = UUID()
        let tabs = makeTabs(count: 6, spaceId: spaceId)

        let plannedTabIDs = TabLazyRestorePlanner.plan(
            anchors: [TabLazyRestoreAnchor(spaceId: spaceId, regularTabId: tabs[2].id)],
            tabsBySpace: [spaceId: tabs],
            fallbackAnchorTabIDsBySpace: [:],
            eligibleTabIDs: Set(tabs.map(\.id)),
            selectedTabIDs: [tabs[2].id],
            visibleTabIDs: [tabs[2].id],
            excludedTabIDs: [],
            maxTotalCount: 5,
            maxAdjacentCountPerAnchor: 5
        )

        XCTAssertEqual(
            plannedTabIDs,
            [tabs[1].id, tabs[3].id, tabs[0].id, tabs[4].id, tabs[5].id]
        )
    }

    func testPlannerCapsTotalAcrossAnchorsAndDeduplicatesResults() {
        let firstSpaceId = UUID()
        let secondSpaceId = UUID()
        let firstTabs = makeTabs(count: 5, spaceId: firstSpaceId)
        let secondTabs = makeTabs(count: 5, spaceId: secondSpaceId)

        let plannedTabIDs = TabLazyRestorePlanner.plan(
            anchors: [
                TabLazyRestoreAnchor(spaceId: firstSpaceId, regularTabId: firstTabs[2].id),
                TabLazyRestoreAnchor(spaceId: secondSpaceId, regularTabId: secondTabs[2].id),
                TabLazyRestoreAnchor(spaceId: firstSpaceId, regularTabId: firstTabs[2].id),
            ],
            tabsBySpace: [
                firstSpaceId: firstTabs,
                secondSpaceId: secondTabs,
            ],
            fallbackAnchorTabIDsBySpace: [:],
            eligibleTabIDs: Set(firstTabs.map(\.id) + secondTabs.map(\.id)),
            selectedTabIDs: [],
            visibleTabIDs: [],
            excludedTabIDs: [],
            maxTotalCount: 4,
            maxAdjacentCountPerAnchor: 3
        )

        XCTAssertEqual(
            plannedTabIDs,
            [firstTabs[1].id, firstTabs[3].id, firstTabs[0].id, secondTabs[1].id]
        )
    }

    func testPlannerFallsBackToSpaceAnchorWhenPreferredRegularTabIsMissing() {
        let spaceId = UUID()
        let tabs = makeTabs(count: 5, spaceId: spaceId)

        let plannedTabIDs = TabLazyRestorePlanner.plan(
            anchors: [TabLazyRestoreAnchor(spaceId: spaceId, regularTabId: nil)],
            tabsBySpace: [spaceId: tabs],
            fallbackAnchorTabIDsBySpace: [spaceId: tabs[3].id],
            eligibleTabIDs: Set(tabs.map(\.id)),
            selectedTabIDs: [],
            visibleTabIDs: [],
            excludedTabIDs: [],
            maxTotalCount: 3,
            maxAdjacentCountPerAnchor: 3
        )

        XCTAssertEqual(plannedTabIDs, [tabs[2].id, tabs[4].id, tabs[1].id])
    }

    private func makeTabs(count: Int, spaceId: UUID) -> [Tab] {
        (0..<count).map { index in
            Tab(
                url: URL(string: "https://\(index).example.com")!,
                name: "Tab \(index)",
                spaceId: spaceId,
                index: index,
                loadsCachedFaviconOnInit: false
            )
        }
    }
}
