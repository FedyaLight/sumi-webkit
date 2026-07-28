import XCTest

@testable import Sumi

@MainActor
final class TabLazyRestoreCoordinatorTests: XCTestCase {
    func testRestoredTabKeepsFaviconRuntimeColdUntilFaviconWorkIsRequested() {
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            loadsCachedFaviconOnInit: false
        )

        XCTAssertFalse(tab.hasMaterializedFaviconRuntime)

        _ = tab.applyCachedFaviconOrPlaceholder(for: tab.url)

        XCTAssertTrue(tab.hasMaterializedFaviconRuntime)
    }

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

    func testCoordinatorWaitsForForegroundLoadBeforeStartingWarmup() async {
        let state = TabStateStore()
        let space = Space(name: "Space")
        let tabs = makeTabs(count: 3, spaceId: space.id)
        state.spaces.replaceSpaces([space])
        state.regularTabs.replaceTabsBySpace(
            [space.id: tabs],
            publish: false
        )
        let runtimeConnection = TabRuntimePortConnection()
        let membership = TabCollectionMembershipOwner(
            structuralLookupOwner: TabStructuralLookupOwner(),
            state: state,
            runtimePreparation: TabRuntimePreparationOwner(
                runtimeConnection: runtimeConnection
            ),
            runtimeConnection: runtimeConnection
        )
        var startedTabIDs: [UUID] = []
        let coordinator = TabLazyRestoreCoordinator(
            spaces: state.spaces,
            regularTabs: state.regularTabs,
            membership: membership,
            policy: TabLazyRestorePolicy(
                maxTotalOpportunisticTabs: 2,
                maxAdjacentTabsPerAnchor: 2,
                maxConcurrentLoads: 1
            ),
            loadWebView: { tab, _ in
                startedTabIDs.append(tab.id)
            }
        )
        let foreground = tabs[1]
        foreground.loadingState = .didStartProvisionalNavigation
        coordinator.reset(restoredTabIDs: Set(tabs.map(\.id)))

        coordinator.refresh(
            anchors: [
                TabLazyRestoreAnchor(
                    spaceId: space.id,
                    regularTabId: foreground.id
                ),
            ],
            selectedTabIDs: [foreground.id],
            visibleTabIDs: [foreground.id]
        )

        XCTAssertTrue(startedTabIDs.isEmpty)

        foreground.loadingState = .didFinish
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(startedTabIDs, [tabs[0].id])
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
