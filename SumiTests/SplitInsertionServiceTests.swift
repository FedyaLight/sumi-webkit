import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SplitInsertionServiceTests: XCTestCase {
    func testCommandTargetIntentMatchesMembership() {
        let memberID = SplitMemberID.regularTab(UUID())

        XCTAssertEqual(
            SplitInsertionTargetResolver.target(
                memberID: memberID,
                side: .right,
                memberIsGrouped: false
            ).intent,
            .firstSplit
        )
        XCTAssertEqual(
            SplitInsertionTargetResolver.target(
                memberID: memberID,
                side: .right,
                memberIsGrouped: true
            ).intent,
            .siblingEdge
        )
    }

    func testEnterSplitCreatesTwoMemberGroupAndActivatesIncomingTab() throws {
        let fixture = try makeFixture()

        XCTAssertTrue(
            fixture.insertion.enterSplit(
                with: fixture.incomingTab,
                side: .right,
                in: fixture.window
            )
        )

        let group = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(
                containing: .regularTab(fixture.currentTab.id)
            )
        )
        XCTAssertEqual(
            group.memberIDs,
            [
                .regularTab(fixture.currentTab.id),
                .regularTab(fixture.incomingTab.id),
            ]
        )
        XCTAssertEqual(
            fixture.window.splitSelection,
            WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(fixture.incomingTab.id)
            )
        )
    }

    func testEnterSplitAddsThirdMemberToExistingGroup() throws {
        let fixture = try makeFixture()
        XCTAssertTrue(
            fixture.insertion.enterSplit(
                with: fixture.incomingTab,
                side: .right,
                in: fixture.window
            )
        )
        let originalGroup = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(
                containing: .regularTab(fixture.currentTab.id)
            )
        )
        let thirdTab = fixture.manager.regularTabLifecycleOwner.createNewTab(
            url: "https://third.example",
            in: fixture.space,
            activate: false
        )

        XCTAssertTrue(
            fixture.insertion.enterSplit(
                with: thirdTab,
                side: .bottom,
                in: fixture.window
            )
        )

        let committedGroup = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: originalGroup.id)
        )
        XCTAssertEqual(committedGroup.id, originalGroup.id)
        XCTAssertEqual(
            Set(committedGroup.memberIDs),
            Set([
                .regularTab(fixture.currentTab.id),
                .regularTab(fixture.incomingTab.id),
                .regularTab(thirdTab.id),
            ])
        )
        XCTAssertEqual(
            fixture.window.splitSelection,
            WindowSplitSelection(
                groupID: originalGroup.id,
                activeMemberID: .regularTab(thirdTab.id)
            )
        )
        guard case .split(let axis, _, let children) =
            committedGroup.layoutTree
        else {
            return XCTFail("Expected a pane-relative split insertion")
        }
        XCTAssertEqual(axis, .row)
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children[0].memberIDs, [.regularTab(fixture.currentTab.id)])
        XCTAssertEqual(
            children[1].memberIDs,
            [
                .regularTab(fixture.incomingTab.id),
                .regularTab(thirdTab.id),
            ]
        )
    }

    func testEmptySplitCreationSplitsActivePaneInsideExistingGroup() throws {
        let fixture = try makeFixture()
        XCTAssertTrue(
            fixture.insertion.enterSplit(
                with: fixture.incomingTab,
                side: .right,
                in: fixture.window
            )
        )
        let originalGroup = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(
                containing: .regularTab(fixture.currentTab.id)
            )
        )

        XCTAssertTrue(
            fixture.emptyPlaceholders.create(
                side: .bottom,
                in: fixture.window
            )
        )

        let committedGroup = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: originalGroup.id)
        )
        let knownMembers: Set<SplitMemberID> = [
            .regularTab(fixture.currentTab.id),
            .regularTab(fixture.incomingTab.id),
        ]
        let placeholderMembers = Set(committedGroup.memberIDs)
            .subtracting(knownMembers)
        XCTAssertEqual(placeholderMembers.count, 1)
        let placeholderMember = try XCTUnwrap(placeholderMembers.first)
        XCTAssertEqual(committedGroup.memberIDs.count, 3)
        XCTAssertEqual(
            fixture.window.splitSelection,
            WindowSplitSelection(
                groupID: originalGroup.id,
                activeMemberID: placeholderMember
            )
        )
        guard case .split(let outerAxis, _, let outerChildren) =
            committedGroup.layoutTree else {
            return XCTFail("Expected the original horizontal split root")
        }
        XCTAssertEqual(outerAxis, .row)
        XCTAssertEqual(outerChildren.count, 2)
        XCTAssertEqual(
            outerChildren[0].memberIDs,
            [.regularTab(fixture.currentTab.id)]
        )
        guard case .split(let innerAxis, _, let innerChildren) =
            outerChildren[1] else {
            return XCTFail("Expected a pane-relative nested split")
        }
        XCTAssertEqual(innerAxis, .column)
        XCTAssertEqual(
            innerChildren.map(\.memberIDs),
            [
                [.regularTab(fixture.incomingTab.id)],
                [placeholderMember],
            ]
        )
    }
}

@MainActor
private extension SplitInsertionServiceTests {
    struct Fixture {
        let manager: TabManager
        let window: BrowserWindowState
        let space: Space
        let currentTab: Tab
        let incomingTab: Tab
        let insertion: SplitInsertionService
        let emptyPlaceholders: EmptySplitService
    }

    func makeFixture() throws -> Fixture {
        let window = BrowserWindowState()
        let manager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            primaryTrackedWindowId: { _ in window.id }
        )
        window.tabManager = manager
        let space = manager.spaceServices.catalog.createSpace(name: "Space")
        let currentTab = manager.regularTabLifecycleOwner.createNewTab(
            url: "https://current.example",
            in: space,
            activate: true
        )
        let incomingTab = manager.regularTabLifecycleOwner.createNewTab(
            url: "https://incoming.example",
            in: space,
            activate: false
        )
        window.currentSpaceId = space.id
        window.currentTabId = currentTab.id

        let tabManager: @MainActor () -> TabManager? = { manager }
        let currentTabInWindow: @MainActor (BrowserWindowState) -> Tab? = {
            state in
            state.currentTabId.flatMap {
                manager.tabCollectionMembershipOwner.tab(for: $0)
            }
        }
        let members = SplitRuntimeMemberResolver(tabManager: tabManager)
        let launcherPlacement = ShortcutSplitLauncherPlacementService(
            tabManager: tabManager
        )
        let presentations = WindowSplitPresentationSynchronizer(
            tabManager: tabManager,
            windows: { [window] },
            selectTabWithoutPersistence: { tab, state in
                _ = WindowTabSelectionStateApplicator.apply(
                    tab,
                    to: state,
                    updateSpaceFromTab: true,
                    rememberSelection: true
                )
            },
            refreshCompositor: { _ in },
            scheduleWindowSession: { _ in },
            persistWindowSession: { _ in }
        )
        let drops = SplitDropService(
            tabManager: tabManager,
            memberResolver: members,
            launcherPlacement: launcherPlacement,
            reconcileAfterCommit: { effect in
                presentations.synchronize(
                    previousGroups: effect.previousGroups,
                    affectedGroupIDs: effect.affectedGroupIDs,
                    preferredSelections: [
                        effect.callerWindowID: WindowSplitSelection(
                            groupID: effect.targetGroupID,
                            activeMemberID: effect.preferredActiveMemberID
                        )
                    ]
                )
            },
            notifyLimit: { _ in }
        )
        let insertion = SplitInsertionService(
            currentTab: currentTabInWindow,
            memberIsGrouped: {
                manager.splitGroupStore.group(containing: $0) != nil
            },
            members: members,
            drops: drops
        )
        let emptyPlaceholders = EmptySplitService(
            tabManager: tabManager,
            currentTab: currentTabInWindow,
            memberResolver: members,
            dropService: drops
        )
        return Fixture(
            manager: manager,
            window: window,
            space: space,
            currentTab: currentTab,
            incomingTab: incomingTab,
            insertion: insertion,
            emptyPlaceholders: emptyPlaceholders
        )
    }
}
