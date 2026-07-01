import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SidebarSplitShortcutRoutingOwnerTests: XCTestCase {
    func testUnloadShortcutHostedSplitGroupWithStaleWindowSpaceDoesNotSelectGlobalFirstTab() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let tabManager = browserManager.tabManager
        let splitManager = browserManager.splitManager
        let otherSpace = tabManager.createSpace(name: "Other")
        let globalFirstTab = tabManager.createNewTab(
            url: "https://other.example",
            in: otherSpace,
            activate: false
        )
        let shortcutPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: otherSpace.id,
            index: 0,
            launchURL: URL(string: "https://shortcut.example")!,
            title: "Shortcut"
        )
        tabManager.setSpacePinnedShortcuts([shortcutPin], for: otherSpace.id)
        let companionTabId = UUID()
        let group = try XCTUnwrap(
            SplitGroup.make(
                tabIds: [shortcutPin.id, companionTabId],
                layoutKind: .vertical,
                host: .shortcutPinned(spaceId: otherSpace.id, profileId: nil, index: 0),
                members: [
                    SplitGroupMember(
                        tabId: shortcutPin.id,
                        pinId: shortcutPin.id,
                        origin: .spacePinned(spaceId: otherSpace.id, folderId: nil, index: 0)
                    ),
                    SplitGroupMember(
                        tabId: companionTabId,
                        pinId: nil,
                        origin: .regular(spaceId: otherSpace.id, index: nil)
                    ),
                ]
            )
        )
        tabManager.upsertSplitGroup(group, schedulePersistence: false)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = UUID()
        windowState.currentTabId = shortcutPin.id
        windowState.currentShortcutPinId = shortcutPin.id
        var selectedTabs: [UUID] = []
        var didShowEmptyState = false

        let owner = BrowserSidebarSplitShortcutRoutingOwner(
            dependencies: BrowserSidebarSplitShortcutRoutingOwner.Dependencies(
                tabManager: { tabManager },
                splitManager: { splitManager },
                space: { spaceId in
                    spaceId.flatMap { requested in
                        tabManager.spaces.first { $0.id == requested }
                    }
                },
                setActiveSpace: { _, _ in /* No-op. */ },
                selectTab: { tab, _ in
                    selectedTabs.append(tab.id)
                },
                refreshCompositor: { _ in /* No-op. */ },
                performImmediateVisualHandoffIfPossible: { _ in /* No-op. */ },
                persistWindowSession: { _ in /* No-op. */ },
                showEmptyState: { windowState in
                    didShowEmptyState = true
                    windowState.isShowingEmptyState = true
                }
            )
        )

        owner.unloadShortcutHostedSplitGroup(group, in: windowState)

        XCTAssertTrue(selectedTabs.isEmpty)
        XCTAssertFalse(selectedTabs.contains(globalFirstTab.id))
        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertTrue(didShowEmptyState)
        XCTAssertTrue(windowState.isShowingEmptyState)
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
