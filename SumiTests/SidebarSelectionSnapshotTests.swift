import Foundation
import Observation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SidebarSelectionSnapshotTests: XCTestCase {
    func testLiveTabIdentityTakesPriorityOverShortcutMetadata() {
        let liveTabID = UUID()
        let pinID = UUID()
        let snapshot = ShortcutSelectionSnapshot(
            currentTabID: liveTabID,
            currentShortcutPinID: UUID()
        )

        XCTAssertTrue(
            ShortcutSelectionIdentity.isSelected(
                tabId: liveTabID,
                pinId: pinID,
                in: snapshot
            )
        )
    }

    func testShortcutMetadataDoesNotOverrideDifferentCurrentTab() {
        let pinID = UUID()
        let snapshot = ShortcutSelectionSnapshot(
            currentTabID: UUID(),
            currentShortcutPinID: pinID
        )

        XCTAssertFalse(
            ShortcutSelectionIdentity.isSelected(
                tabId: UUID(),
                pinId: pinID,
                in: snapshot
            )
        )
    }

    func testShortcutMetadataIsFallbackWhenExactCurrentTabIsAbsent() {
        let pinID = UUID()
        let snapshot = ShortcutSelectionSnapshot(
            currentShortcutPinID: pinID
        )

        XCTAssertTrue(
            ShortcutSelectionIdentity.isSelected(
                tabId: UUID(),
                pinId: pinID,
                in: snapshot
            )
        )
    }

    func testEmptySnapshotClearsShortcutSelection() {
        XCTAssertFalse(
            ShortcutSelectionIdentity.isSelected(
                tabId: UUID(),
                pinId: UUID(),
                in: ShortcutSelectionSnapshot()
            )
        )
    }

    func testSnapshotReadIsInvalidatedByWindowSelectionChange() {
        let window = BrowserWindowState()
        let invalidated = expectation(description: "selection snapshot invalidated")

        withObservationTracking {
            _ = SidebarWindowSelectionSnapshot(windowState: window)
        } onChange: {
            invalidated.fulfill()
        }
        window.currentTabId = UUID()

        wait(for: [invalidated], timeout: 1)
    }

    func testSidebarSnapshotSelectsOnlyActiveSplitMember() throws {
        let browser = BrowserManager()
        let window = BrowserWindowState()
        browser.windowRegistry.register(window)
        let query = SidebarWindowSelectionQuery(
            runtimeIsAlive: { true },
            windows: SidebarWindowIdentityQuery(registry: browser.windowRegistry),
            windowTabs: browser.windowTabContext,
            shortcutPresentation: browser.shortcutPresentationOwner,
            splitQuery: browser.splitQuery
        )
        let spaceID = UUID()
        let activePinID = UUID()
        let activeMemberID = SplitMemberID.shortcutPin(activePinID)
        let activeMember = SplitMember.shortcutPin(activePinID)
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [activeMember, .regularTab(UUID())],
                layoutKind: .horizontal,
                container: .regularTabs(spaceId: spaceID)
            )
        )
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        window.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: activeMemberID
        )
        let snapshot = SidebarWindowSelectionSnapshot(
            splitSelection: WindowSplitSelection(
                groupID: group.id,
                activeMemberID: activeMemberID
            )
        )

        XCTAssertTrue(
            query.isSplitMemberSelected(
                groupID: group.id,
                memberID: activeMemberID,
                in: window,
                selection: snapshot
            )
        )
        XCTAssertFalse(
            query.isSplitMemberSelected(
                groupID: group.id,
                memberID: .regularTab(UUID()),
                in: window,
                selection: snapshot
            )
        )
    }
}
