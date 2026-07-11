import Foundation
import SumiDomain
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SplitEmptyPlaceholderOwnerTests: XCTestCase {
    private struct Harness {
        let tabManager: TabManager
        let owner: SplitEmptyPlaceholderOwner
        let windowState: BrowserWindowState
        let selectedTabIds: () -> [UUID]
        let notifiedWindowIds: () -> [UUID]
    }

    private func makeHarness() throws -> Harness {
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        tabManager.runtimePortsAttachmentOwner.attach(TestRuntimePorts.inactive)
        let windowState = BrowserWindowState()
        windowState.tabManager = tabManager

        final class Recorder {
            var selectedTabIds: [UUID] = []
            var notifiedWindowIds: [UUID] = []
        }
        let recorder = Recorder()
        let owner = SplitEmptyPlaceholderOwner(
            tabManager: { [weak tabManager] in tabManager },
            membershipResolution: SplitMembershipResolutionOwner(
                tabManager: { [weak tabManager] in tabManager }
            ),
            selectTab: { tab, _ in recorder.selectedTabIds.append(tab.id) },
            notifyChanged: { recorder.notifiedWindowIds.append($0) }
        )
        return Harness(
            tabManager: tabManager,
            owner: owner,
            windowState: windowState,
            selectedTabIds: { recorder.selectedTabIds },
            notifiedWindowIds: { recorder.notifiedWindowIds }
        )
    }

    private func makePlaceholderSplit(
        in harness: Harness
    ) throws -> (current: Tab, placeholder: Tab, group: SplitGroup) {
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Split")
        let current = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://current.example", in: space)
        let placeholder = harness.tabManager.regularTabLifecycleOwner.createNewTab(
            url: SumiSurface.emptyTabURL.absoluteString,
            in: space,
            activate: false
        )
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = current.id
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [current.id, placeholder.id],
            layoutKind: .vertical,
            activeTabId: placeholder.id,
            host: .regular(spaceId: space.id)
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)
        harness.owner.registerPlaceholder(tabId: placeholder.id, for: harness.windowState.id)
        return (current, placeholder, group)
    }

    func testReplacePlaceholderSwapsPaneAndRemovesPlaceholderTab() throws {
        let harness = try makeHarness()
        let (current, placeholder, group) = try makePlaceholderSplit(in: harness)
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://incoming.example",
            in: harness.tabManager.spaceStateOwner.currentSpace,
            activate: false
        )

        XCTAssertTrue(harness.owner.replacePlaceholder(with: incoming, in: harness.windowState))

        let updated = try XCTUnwrap(harness.tabManager.splitGroupCollectionStateOwner.group(with: group.id))
        XCTAssertEqual(updated.tabIds, [current.id, incoming.id])
        XCTAssertEqual(updated.activeTabId, incoming.id)
        XCTAssertNil(harness.tabManager.tabCollectionMembershipOwner.tab(for: placeholder.id))
        XCTAssertEqual(harness.selectedTabIds(), [incoming.id])
        XCTAssertEqual(harness.notifiedWindowIds(), [harness.windowState.id])
    }

    func testCommitPlaceholderStopsLaterReplacement() throws {
        let harness = try makeHarness()
        let (_, placeholder, _) = try makePlaceholderSplit(in: harness)
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://incoming.example",
            in: harness.tabManager.spaceStateOwner.currentSpace,
            activate: false
        )

        harness.owner.commitPlaceholder(tabId: placeholder.id, in: harness.windowState)

        XCTAssertFalse(harness.owner.replacePlaceholder(with: incoming, in: harness.windowState))
        XCTAssertNotNil(harness.tabManager.tabCollectionMembershipOwner.tab(for: placeholder.id))
    }

    func testCommitPlaceholderIgnoresMismatchedTabId() throws {
        let harness = try makeHarness()
        _ = try makePlaceholderSplit(in: harness)
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://incoming.example",
            in: harness.tabManager.spaceStateOwner.currentSpace,
            activate: false
        )

        harness.owner.commitPlaceholder(tabId: UUID(), in: harness.windowState)

        XCTAssertTrue(harness.owner.replacePlaceholder(with: incoming, in: harness.windowState))
    }

    func testCancelPlaceholderRemovesPlaceholderTab() throws {
        let harness = try makeHarness()
        let (_, placeholder, _) = try makePlaceholderSplit(in: harness)

        XCTAssertTrue(harness.owner.cancelPlaceholder(in: harness.windowState))

        XCTAssertNil(harness.tabManager.tabCollectionMembershipOwner.tab(for: placeholder.id))
        XCTAssertEqual(harness.notifiedWindowIds(), [harness.windowState.id])
        XCTAssertFalse(harness.owner.cancelPlaceholder(in: harness.windowState))
    }

    func testCleanupWindowDropsRegistration() throws {
        let harness = try makeHarness()
        let (_, placeholder, _) = try makePlaceholderSplit(in: harness)

        harness.owner.cleanupWindow(harness.windowState.id)

        XCTAssertFalse(harness.owner.cancelPlaceholder(in: harness.windowState))
        XCTAssertNotNil(harness.tabManager.tabCollectionMembershipOwner.tab(for: placeholder.id))
    }
}
