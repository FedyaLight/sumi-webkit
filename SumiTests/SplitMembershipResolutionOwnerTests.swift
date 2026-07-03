import Foundation
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SplitMembershipResolutionOwnerTests: XCTestCase {
    private struct Harness {
        let tabManager: TabManager
        let owner: SplitMembershipResolutionOwner
        let windowState: BrowserWindowState
    }

    private func makeHarness() throws -> Harness {
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        tabManager.attachRuntimeContext(TabManagerRuntimeContext())
        let windowState = BrowserWindowState()
        windowState.tabManager = tabManager
        let owner = SplitMembershipResolutionOwner(
            tabManager: { [weak tabManager] in tabManager }
        )
        return Harness(tabManager: tabManager, owner: owner, windowState: windowState)
    }

    func testRegularTabResolvesToItselfWithRegularOrigin() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        let tab = harness.tabManager.createNewTab(url: "https://a.example", in: space)
        harness.windowState.currentSpaceId = space.id

        let resolved = try XCTUnwrap(harness.owner.resolvedSplitTab(
            tab,
            host: .regular(spaceId: space.id),
            sourceGroup: nil,
            in: harness.windowState
        ))

        XCTAssertEqual(resolved.tab.id, tab.id)
        XCTAssertNil(resolved.member.pinId)
        XCTAssertEqual(resolved.member.tabId, tab.id)
        XCTAssertEqual(resolved.member.origin, .regular(spaceId: tab.spaceId, index: tab.index))
    }

    func testInitialHostForRegularTabsUsesTargetSpace() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        let incoming = harness.tabManager.createNewTab(url: "https://a.example", in: space)
        let target = harness.tabManager.createNewTab(url: "https://b.example", in: space)

        let host = harness.owner.initialHost(for: incoming, targetTab: target, in: harness.windowState)

        XCTAssertEqual(host, .regular(spaceId: space.id))
    }

    func testSourceSplitGroupAndRemovalIdForDirectMember() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        let first = harness.tabManager.createNewTab(url: "https://a.example", in: space)
        let second = harness.tabManager.createNewTab(url: "https://b.example", in: space, activate: false)
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [first.id, second.id],
            layoutKind: .vertical,
            activeTabId: first.id,
            host: .regular(spaceId: space.id)
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let sourceGroup = try XCTUnwrap(harness.owner.sourceSplitGroup(for: second))
        XCTAssertEqual(sourceGroup.id, group.id)
        XCTAssertEqual(harness.owner.sourceRemovalId(for: second, in: sourceGroup), second.id)

        let outsider = harness.tabManager.createNewTab(url: "https://c.example", in: space, activate: false)
        XCTAssertNil(harness.owner.sourceSplitGroup(for: outsider))
        XCTAssertNil(harness.owner.sourceRemovalId(for: outsider, in: sourceGroup))
        XCTAssertNil(harness.owner.sourceRemovalId(for: outsider, in: nil))
    }

    func testPreferredFocusTabAfterUnsplitPrefersCurrentThenActiveThenFirstResolvable() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        let first = harness.tabManager.createNewTab(url: "https://a.example", in: space)
        let second = harness.tabManager.createNewTab(url: "https://b.example", in: space, activate: false)
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [first.id, second.id],
            layoutKind: .vertical,
            activeTabId: second.id,
            host: .regular(spaceId: space.id)
        ))

        harness.windowState.currentTabId = first.id
        XCTAssertEqual(
            harness.owner.preferredFocusTabAfterUnsplit(group, in: harness.windowState)?.id,
            first.id
        )

        harness.windowState.currentTabId = nil
        XCTAssertEqual(
            harness.owner.preferredFocusTabAfterUnsplit(group, in: harness.windowState)?.id,
            second.id,
            "Without a current tab the group's active tab wins."
        )

        harness.tabManager.removeTab(second.id)
        XCTAssertEqual(
            harness.owner.preferredFocusTabAfterUnsplit(group, in: harness.windowState)?.id,
            first.id,
            "When the active tab is gone the first resolvable member wins."
        )
    }
}
