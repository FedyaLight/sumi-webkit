import XCTest

@testable import Sumi

@MainActor
final class ShortcutTabBindingSynchronizerTests: XCTestCase {
    func testRefreshMovesRuntimeBindingWithoutSwitchingBackgroundWindowSpace() throws {
        let window = BrowserWindowState()
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        window.tabManager = tabManager
        let sourceSpace = tabManager.spaceServices.catalog.createSpace(name: "Source")
        let visibleSpace = tabManager.spaceServices.catalog.createSpace(name: "Visible")
        let targetSpace = tabManager.spaceServices.catalog.createSpace(name: "Target")
        let source = makePin(spaceId: sourceSpace.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )
        window.currentSpaceId = visibleSpace.id
        window.currentTabId = UUID()
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role
        let moved = source.moved(to: targetSpace.id)

        tabManager.shortcutTabBindings.refreshInstances(for: moved)

        XCTAssertEqual(liveTab.spaceId, targetSpace.id)
        XCTAssertEqual(window.currentSpaceId, visibleSpace.id)
        XCTAssertEqual(liveTab.shortcutPinId, moved.id)
        XCTAssertEqual(liveTab.shortcutPinRole, .spacePinned)
    }

    func testRebindDoesNotTreatStaleShortcutMetadataAsSelection() throws {
        let window = BrowserWindowState()
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        window.tabManager = tabManager
        let sourceSpace = tabManager.spaceServices.catalog.createSpace(name: "Source")
        let visibleSpace = tabManager.spaceServices.catalog.createSpace(name: "Visible")
        let targetSpace = tabManager.spaceServices.catalog.createSpace(name: "Target")
        let source = makePin(spaceId: sourceSpace.id)
        let target = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: targetSpace.id,
            index: 0,
            launchURL: source.launchURL,
            title: source.title
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )
        let selectedTabId = UUID()
        window.currentSpaceId = visibleSpace.id
        window.currentTabId = selectedTabId
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role

        XCTAssertTrue(
            tabManager.shortcutTabBindings.rebind(
                liveTab,
                from: source,
                to: target
            )
        )

        XCTAssertEqual(window.currentSpaceId, visibleSpace.id)
        XCTAssertEqual(window.currentTabId, selectedTabId)
        XCTAssertNil(window.currentShortcutPinId)
        XCTAssertNil(window.currentShortcutPinRole)
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: target.id, in: window.id),
            liveTab
        )
    }

    func testRefreshSwitchesSpaceOnlyForSelectedLiveInstance() throws {
        let window = BrowserWindowState()
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        window.tabManager = tabManager
        let sourceSpace = tabManager.spaceServices.catalog.createSpace(name: "Source")
        let targetSpace = tabManager.spaceServices.catalog.createSpace(name: "Target")
        let source = makePin(spaceId: sourceSpace.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )
        window.currentSpaceId = sourceSpace.id
        window.currentTabId = liveTab.id
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role
        let moved = source.moved(to: targetSpace.id)

        tabManager.shortcutTabBindings.refreshInstances(for: moved)

        XCTAssertEqual(window.currentSpaceId, targetSpace.id)
        XCTAssertEqual(window.currentShortcutPinRole, .spacePinned)
    }

    func testRebindRekeysExactInstanceAndRepairsSelectionMetadata() throws {
        let window = BrowserWindowState()
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        window.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = makePin(spaceId: space.id)
        let target = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: UUID(),
            index: 0,
            launchURL: source.launchURL,
            title: source.title
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: space.id
        )
        window.currentTabId = liveTab.id
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role
        window.selectionHistory.recentSelectionItemsBySpace[space.id] = [
            .shortcutPin(source.id),
        ]

        XCTAssertTrue(
            tabManager.shortcutTabBindings.rebind(
                liveTab,
                from: source,
                to: target
            )
        )

        XCTAssertNil(tabManager.liveShortcutTabs.tab(for: source.id, in: window.id))
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: target.id, in: window.id),
            liveTab
        )
        XCTAssertEqual(window.currentShortcutPinId, target.id)
        XCTAssertEqual(window.currentShortcutPinRole, .essential)
        XCTAssertNil(liveTab.spaceId)
        XCTAssertNil(liveTab.folderId)
        XCTAssertEqual(
            window.selectionHistory.recentSelectionItemsBySpace[space.id],
            [.shortcutPin(target.id)]
        )
    }

    func testHistoryOnlyRefreshDoesNotPersistWindowSession() throws {
        let window = BrowserWindowState()
        var persistedWindowIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        )
        window.tabManager = tabManager
        let sourceSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Source"
        )
        let targetSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Target"
        )
        let source = makePin(spaceId: sourceSpace.id)
        _ = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )
        window.currentSpaceId = sourceSpace.id
        window.currentTabId = UUID()
        window.selectionHistory.recentSelectionItemsBySpace[sourceSpace.id] = [
            .shortcutPin(source.id),
        ]

        tabManager.shortcutTabBindings.refreshInstances(
            for: source.moved(to: targetSpace.id)
        )

        XCTAssertTrue(persistedWindowIds.isEmpty)
        XCTAssertNil(
            window.selectionHistory.recentSelectionItemsBySpace[sourceSpace.id]
        )
        XCTAssertEqual(
            window.selectionHistory.recentSelectionItemsBySpace[targetSpace.id],
            [.shortcutPin(source.id)]
        )
    }

    private func makePin(spaceId: UUID) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: 0,
            launchURL: URL(string: "https://binding.example")!,
            title: "Binding"
        )
    }
}

private extension ShortcutPin {
    func moved(to spaceId: UUID) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: .spacePinned,
            executionProfileId: executionProfileId,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: launchURL,
            title: title,
            iconAsset: iconAsset
        )
    }
}
