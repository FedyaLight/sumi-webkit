import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SidebarDragCurrentContextTests: XCTestCase {
    func testRegularTabReorderStaysInsideCurrentSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let first = tabManager.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.createNewTab(url: "https://example.com/three", in: space, activate: false)
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(first)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(first),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 3
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.id), [second.id, third.id, first.id])
        XCTAssertTrue(tabManager.spacePinnedPins(for: space.id).isEmpty)
    }

    func testRegularTabDropIntoSpacePinnedCreatesLauncherAndRemovesRegularEntry() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let tab = tabManager.createNewTab(url: "https://example.com/pin", in: space)
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
        let pin = try XCTUnwrap(tabManager.spacePinnedPins(for: space.id).first)
        XCTAssertEqual(pin.role, .spacePinned)
        XCTAssertEqual(pin.spaceId, space.id)
        XCTAssertNil(pin.folderId)
        XCTAssertEqual(pin.launchURL, tab.url)
    }

    func testRegularTabDropIntoFolderCreatesFolderLauncher() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let tab = tabManager.createNewTab(url: "https://example.com/folder", in: space)
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
        let pin = try XCTUnwrap(tabManager.folderPinnedPins(for: folder.id, in: space.id).first)
        XCTAssertEqual(pin.role, .spacePinned)
        XCTAssertEqual(pin.spaceId, space.id)
        XCTAssertEqual(pin.folderId, folder.id)
        XCTAssertEqual(pin.launchURL, tab.url)
    }

    func testRegularTabDropIntoEssentialsCreatesProfileLauncher() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let tab = tabManager.createNewTab(url: "https://example.com/essential", in: space)
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .essentials,
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
        let pin = try XCTUnwrap(tabManager.essentialPins(for: profileId).first)
        XCTAssertEqual(pin.role, .essential)
        XCTAssertEqual(pin.profileId, profileId)
        XCTAssertNil(pin.spaceId)
        XCTAssertNil(pin.folderId)
        XCTAssertEqual(pin.launchURL, tab.url)
    }

    func testDisplayedRegularTabDropIntoSpacePinnedPreservesTabAsLiveShortcut() throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let tab = tabManager.createNewTab(url: "https://example.com/live-pin", in: space)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = tab.id
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
        let pin = try XCTUnwrap(tabManager.spacePinnedPins(for: space.id).first)
        let liveTab = try XCTUnwrap(tabManager.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        XCTAssertTrue(liveTab === tab)
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        XCTAssertEqual(liveTab.shortcutPinRole, .spacePinned)
        XCTAssertTrue(liveTab.isShortcutLiveInstance)
        XCTAssertEqual(liveTab.spaceId, space.id)
        XCTAssertNil(liveTab.folderId)
        XCTAssertEqual(harness.windowState.currentTabId, tab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, .spacePinned)
    }

    func testDisplayedRegularTabDropIntoFolderPreservesTabAsLiveShortcut() throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let tab = tabManager.createNewTab(url: "https://example.com/live-folder", in: space)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = tab.id
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
        let pin = try XCTUnwrap(tabManager.folderPinnedPins(for: folder.id, in: space.id).first)
        let liveTab = try XCTUnwrap(tabManager.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        XCTAssertTrue(liveTab === tab)
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        XCTAssertEqual(liveTab.shortcutPinRole, .spacePinned)
        XCTAssertTrue(liveTab.isShortcutLiveInstance)
        XCTAssertEqual(liveTab.spaceId, space.id)
        XCTAssertEqual(liveTab.folderId, folder.id)
        XCTAssertEqual(harness.windowState.currentTabId, tab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, .spacePinned)
    }

    func testDisplayedRegularTabDropIntoEssentialsPreservesTabAsLiveShortcut() throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let tab = tabManager.createNewTab(url: "https://example.com/live-essential", in: space)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = tab.id
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .essentials,
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
        let pin = try XCTUnwrap(tabManager.essentialPins(for: profileId).first)
        let liveTab = try XCTUnwrap(tabManager.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        XCTAssertTrue(liveTab === tab)
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        XCTAssertEqual(liveTab.shortcutPinRole, .essential)
        XCTAssertTrue(liveTab.isShortcutLiveInstance)
        XCTAssertNil(liveTab.spaceId)
        XCTAssertNil(liveTab.folderId)
        XCTAssertEqual(harness.windowState.currentTabId, tab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, .essential)
    }

    func testNonDisplayedRegularTabDropIntoShortcutSectionsCreatesLauncherWithoutLiveTab() throws {
        try assertNonDisplayedRegularTabConversionCreatesLauncherOnly(target: .spacePinned)
        try assertNonDisplayedRegularTabConversionCreatesLauncherOnly(target: .folder)
        try assertNonDisplayedRegularTabConversionCreatesLauncherOnly(target: .essentials)
    }

    func testSpacePinnedReorderMovesLauncherWithinSameSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let first = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/one",
            index: 0
        )
        let second = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/two",
            index: 1
        )
        let third = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/three",
            index: 2
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: dragItem(first)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(first),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 3
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(tabManager.spacePinnedPins(for: space.id).map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(tabManager.spacePinnedPins(for: space.id).map(\.index), [0, 1, 2])
        XCTAssertTrue(tabManager.spacePinnedPins(for: space.id).allSatisfy { $0.folderId == nil })
    }

    func testEssentialsReorderMovesLauncherWithinSameProfile() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let first = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/one",
            index: 0
        )
        let second = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/two",
            index: 1
        )
        let third = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/three",
            index: 2
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .essentials,
            item: dragItem(first)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(first),
                scope: scope,
                fromContainer: .essentials,
                toContainer: .essentials,
                toIndex: 3
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(tabManager.essentialPins(for: profileId).map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(tabManager.essentialPins(for: profileId).map(\.index), [0, 1, 2])
        XCTAssertTrue(tabManager.essentialPins(for: profileId).allSatisfy { $0.profileId == profileId })
    }

    func testFolderChildReorderMovesLauncherWithinSameFolder() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let first = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/one",
            index: 0
        )
        let second = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/two",
            index: 1
        )
        let third = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/three",
            index: 2
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .folder(folder.id),
            item: dragItem(first)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(first),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .folder(folder.id),
                toIndex: 3
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(tabManager.folderPinnedPins(for: folder.id, in: space.id).map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(tabManager.folderPinnedPins(for: folder.id, in: space.id).map(\.index), [0, 1, 2])
        XCTAssertTrue(tabManager.folderPinnedPins(for: folder.id, in: space.id).allSatisfy { $0.folderId == folder.id })
    }

    func testFolderHeaderReorderMovesFolderWithinTopLevelPinnedSection() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let first = tabManager.createFolder(for: space.id, name: "One")
        let second = tabManager.createFolder(for: space.id, name: "Two")
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: dragItem(first)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .folder(first),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 2
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(topLevelPinnedItemIDs(tabManager, in: space.id), [second.id, first.id])
        XCTAssertEqual(tabManager.folders(for: space.id).map(\.index), [0, 1])
    }

    func testSpacePinnedDropIntoFolderPreservesLauncherAndMovesOwnership() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let existingFolderPin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/existing-folder",
            index: 0
        )
        let pin = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/pinned",
            index: 1
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(topLevelPinnedItemIDs(tabManager, in: space.id), [folder.id])
        let folderPins = tabManager.folderPinnedPins(for: folder.id, in: space.id)
        XCTAssertEqual(folderPins.map(\.id), [pin.id, existingFolderPin.id])
        let moved = try XCTUnwrap(folderPins.first)
        XCTAssertEqual(moved.role, .spacePinned)
        XCTAssertEqual(moved.spaceId, space.id)
        XCTAssertEqual(moved.folderId, folder.id)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
    }

    func testSpacePinnedDropIntoEssentialsPreservesLauncherAndMovesOwnership() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let existingEssential = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/existing-essential",
            index: 0
        )
        let pin = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/pinned",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .essentials,
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.spacePinnedPins(for: space.id).isEmpty)
        let essentials = tabManager.essentialPins(for: profileId)
        XCTAssertEqual(essentials.map(\.id), [pin.id, existingEssential.id])
        let moved = try XCTUnwrap(essentials.first)
        XCTAssertEqual(moved.role, .essential)
        XCTAssertEqual(moved.profileId, profileId)
        XCTAssertNil(moved.spaceId)
        XCTAssertNil(moved.folderId)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
    }

    func testFolderChildDropIntoSpacePinnedPreservesLauncherAndMovesOwnership() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let pin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/folder-child",
            index: 0
        )
        let existingTopLevelPin = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/top-level",
            index: 1
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .folder(folder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .spacePinned(space.id),
                toIndex: 1
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.folderPinnedPins(for: folder.id, in: space.id).isEmpty)
        XCTAssertEqual(topLevelPinnedItemIDs(tabManager, in: space.id), [folder.id, pin.id, existingTopLevelPin.id])
        let moved = try XCTUnwrap(tabManager.spacePinnedPins(for: space.id).first { $0.id == pin.id })
        XCTAssertEqual(moved.role, .spacePinned)
        XCTAssertEqual(moved.spaceId, space.id)
        XCTAssertNil(moved.folderId)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
    }

    func testFolderChildDropIntoEssentialsPreservesLauncherAndMovesOwnership() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let existingEssential = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/existing-essential",
            index: 0
        )
        let pin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/folder-child",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .folder(folder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .essentials,
                toIndex: 1
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.folderPinnedPins(for: folder.id, in: space.id).isEmpty)
        let essentials = tabManager.essentialPins(for: profileId)
        XCTAssertEqual(essentials.map(\.id), [existingEssential.id, pin.id])
        let moved = try XCTUnwrap(essentials.first { $0.id == pin.id })
        XCTAssertEqual(moved.role, .essential)
        XCTAssertEqual(moved.profileId, profileId)
        XCTAssertNil(moved.spaceId)
        XCTAssertNil(moved.folderId)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
    }

    func testEssentialDropIntoSpacePinnedPreservesLauncherAndMovesOwnership() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let existingTopLevelPin = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/top-level",
            index: 1
        )
        let pin = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/essential",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .essentials,
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .essentials,
                toContainer: .spacePinned(space.id),
                toIndex: 1
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.essentialPins(for: profileId).isEmpty)
        XCTAssertEqual(topLevelPinnedItemIDs(tabManager, in: space.id), [folder.id, pin.id, existingTopLevelPin.id])
        let moved = try XCTUnwrap(tabManager.spacePinnedPins(for: space.id).first { $0.id == pin.id })
        XCTAssertEqual(moved.role, .spacePinned)
        XCTAssertEqual(moved.spaceId, space.id)
        XCTAssertNil(moved.profileId)
        XCTAssertNil(moved.folderId)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
    }

    func testEssentialDropIntoFolderPreservesLauncherAndMovesOwnership() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let existingFolderPin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/existing-folder",
            index: 0
        )
        let pin = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/essential",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .essentials,
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .essentials,
                toContainer: .folder(folder.id),
                toIndex: 1
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.essentialPins(for: profileId).isEmpty)
        let folderPins = tabManager.folderPinnedPins(for: folder.id, in: space.id)
        XCTAssertEqual(folderPins.map(\.id), [existingFolderPin.id, pin.id])
        let moved = try XCTUnwrap(folderPins.first { $0.id == pin.id })
        XCTAssertEqual(moved.role, .spacePinned)
        XCTAssertEqual(moved.spaceId, space.id)
        XCTAssertNil(moved.profileId)
        XCTAssertEqual(moved.folderId, folder.id)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
    }

    func testFolderChildDropIntoDifferentFolderPreservesLauncherAndMovesOwnership() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let sourceFolder = tabManager.createFolder(for: space.id, name: "Source")
        let targetFolder = tabManager.createFolder(for: space.id, name: "Target")
        let pin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: sourceFolder.id,
            url: "https://example.com/source-child",
            index: 0
        )
        let existingTargetPin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: targetFolder.id,
            url: "https://example.com/target-child",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .folder(sourceFolder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .folder(sourceFolder.id),
                toContainer: .folder(targetFolder.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.folderPinnedPins(for: sourceFolder.id, in: space.id).isEmpty)
        let targetPins = tabManager.folderPinnedPins(for: targetFolder.id, in: space.id)
        XCTAssertEqual(targetPins.map(\.id), [pin.id, existingTargetPin.id])
        let moved = try XCTUnwrap(targetPins.first)
        XCTAssertEqual(moved.role, .spacePinned)
        XCTAssertEqual(moved.spaceId, space.id)
        XCTAssertEqual(moved.folderId, targetFolder.id)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
    }

    func testSpacePinnedDropIntoRegularCreatesRegularTabAndRemovesLauncherOwnership() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let pin = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/pinned",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.spacePinnedPins(for: space.id).isEmpty)
        let converted = try XCTUnwrap(tabManager.tabsBySpace[space.id]?.first)
        XCTAssertEqual(converted.url, pin.launchURL)
        XCTAssertNil(converted.shortcutPinId)
        XCTAssertFalse(converted.isShortcutLiveInstance)
    }

    func testFolderChildDropIntoRegularCreatesRegularTabAndRemovesFolderOwnership() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let pin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/folder",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .folder(folder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.folderPinnedPins(for: folder.id, in: space.id).isEmpty)
        let converted = try XCTUnwrap(tabManager.tabsBySpace[space.id]?.first)
        XCTAssertEqual(converted.url, pin.launchURL)
        XCTAssertNil(converted.folderId)
        XCTAssertNil(converted.shortcutPinId)
        XCTAssertFalse(converted.isShortcutLiveInstance)
    }

    func testEssentialDropIntoRegularCreatesRegularTabAndRemovesEssentialOwnership() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let pin = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/essential",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .essentials,
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .essentials,
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.essentialPins(for: profileId).isEmpty)
        let converted = try XCTUnwrap(tabManager.tabsBySpace[space.id]?.first)
        XCTAssertEqual(converted.url, pin.launchURL)
        XCTAssertNil(converted.shortcutPinId)
        XCTAssertFalse(converted.isShortcutLiveInstance)
    }

    func testSpacePinnedWithLiveShortcutDropIntoRegularReusesLiveTabAndClearsBinding() throws {
        try assertLiveLauncherDropIntoRegularReusesLiveTab(source: .spacePinned)
    }

    func testFolderChildWithLiveShortcutDropIntoRegularReusesLiveTabAndClearsBinding() throws {
        try assertLiveLauncherDropIntoRegularReusesLiveTab(source: .folder)
    }

    func testEssentialWithLiveShortcutDropIntoRegularReusesLiveTabAndClearsBinding() throws {
        try assertLiveLauncherDropIntoRegularReusesLiveTab(source: .essentials)
    }

    func testLauncherWithoutLiveShortcutDropIntoRegularCreatesNewRegularTab() throws {
        try assertLauncherWithoutLiveShortcutDropIntoRegularCreatesNewTab(source: .spacePinned)
        try assertLauncherWithoutLiveShortcutDropIntoRegularCreatesNewTab(source: .folder)
        try assertLauncherWithoutLiveShortcutDropIntoRegularCreatesNewTab(source: .essentials)
    }

    func testMovingLiveLauncherBetweenShortcutSectionsPreservesLiveBinding() throws {
        try assertLiveLauncherMovePreservesBinding(source: .spacePinned, destination: .folder)
        try assertLiveLauncherMovePreservesBinding(source: .folder, destination: .essentials)
        try assertLiveLauncherMovePreservesBinding(source: .essentials, destination: .spacePinned)
    }

    func testWrongProfileScopeIsRejectedEvenWhenSpaceMatches() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let wrongProfileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let tab = tabManager.createNewTab(url: "https://example.com/source", in: space)
        let scope = try makeScope(
            spaceId: space.id,
            profileId: wrongProfileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        )

        XCTAssertFalse(didMove)
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.id), [tab.id])
        XCTAssertTrue(tabManager.spacePinnedPins(for: space.id).isEmpty)
    }

    func testMismatchedSourceContainerIsRejectedEvenWhenTargetIsCurrentSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let tab = tabManager.createNewTab(url: "https://example.com/source", in: space)
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        )

        XCTAssertFalse(didMove)
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.id), [tab.id])
        XCTAssertTrue(tabManager.spacePinnedPins(for: space.id).isEmpty)
    }

    func testCrossSpaceDropTargetIsRejected() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let sourceSpace = tabManager.createSpace(name: "Source", profileId: profileId)
        let targetSpace = tabManager.createSpace(name: "Target", profileId: profileId)
        let tab = tabManager.createNewTab(url: "https://example.com/source", in: sourceSpace)
        let scope = try makeScope(
            spaceId: sourceSpace.id,
            profileId: profileId,
            sourceZone: .spaceRegular(sourceSpace.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(sourceSpace.id),
                toContainer: .spaceRegular(targetSpace.id),
                toIndex: 0
            )
        )

        XCTAssertFalse(didMove)
        XCTAssertEqual(tabManager.tabsBySpace[sourceSpace.id]?.map(\.id), [tab.id])
        XCTAssertTrue(tabManager.tabsBySpace[targetSpace.id]?.isEmpty ?? true)
    }

    func testPayloadFromDifferentSpaceIsRejectedEvenWhenSourceScopeNamesCurrentSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let sourceSpace = tabManager.createSpace(name: "Source", profileId: profileId)
        let otherSpace = tabManager.createSpace(name: "Other", profileId: profileId)
        let sourceTab = tabManager.createNewTab(url: "https://example.com/source", in: sourceSpace)
        let otherTab = tabManager.createNewTab(url: "https://example.com/other", in: otherSpace)
        let scope = try makeScope(
            spaceId: sourceSpace.id,
            profileId: profileId,
            sourceZone: .spaceRegular(sourceSpace.id),
            item: dragItem(otherTab)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(otherTab),
                scope: scope,
                fromContainer: .spaceRegular(sourceSpace.id),
                toContainer: .spacePinned(sourceSpace.id),
                toIndex: 0
            )
        )

        XCTAssertFalse(didMove)
        XCTAssertEqual(tabManager.tabsBySpace[sourceSpace.id]?.map(\.id), [sourceTab.id])
        XCTAssertEqual(tabManager.tabsBySpace[otherSpace.id]?.map(\.id), [otherTab.id])
        XCTAssertTrue(tabManager.spacePinnedPins(for: sourceSpace.id).isEmpty)
    }

    private func makeInMemoryTabManager() throws -> TabManager {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return TabManager(context: container.mainContext, loadPersistedState: false)
    }

    private func makeLiveWindowHarness() throws -> LiveWindowHarness {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let browserManager = BrowserManager()
        let tabManager = TabManager(
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState()
        windowState.tabManager = tabManager
        browserManager.tabManager = tabManager
        browserManager.windowRegistry = windowRegistry
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        return LiveWindowHarness(
            browserManager: browserManager,
            tabManager: tabManager,
            windowRegistry: windowRegistry,
            windowState: windowState
        )
    }

    private func makeScope(
        spaceId: UUID,
        profileId: UUID,
        sourceZone: DropZoneID,
        item: SumiDragItem
    ) throws -> SidebarDragScope {
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = spaceId
        windowState.currentProfileId = profileId
        return try XCTUnwrap(
            SidebarDragScope(
                windowState: windowState,
                sourceZone: sourceZone,
                item: item
            )
        )
    }

    private func dragItem(_ tab: Tab) -> SumiDragItem {
        SumiDragItem(
            tabId: tab.id,
            title: tab.name,
            urlString: tab.url.absoluteString
        )
    }

    private func dragItem(_ pin: ShortcutPin) -> SumiDragItem {
        SumiDragItem(
            tabId: pin.id,
            title: pin.title,
            urlString: pin.launchURL.absoluteString
        )
    }

    private func dragItem(_ folder: TabFolder) -> SumiDragItem {
        SumiDragItem.folder(folderId: folder.id, title: folder.name)
    }

    private func makeSpacePinnedPin(
        _ tabManager: TabManager,
        in space: Space,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = tabManager.createNewTab(url: url, in: space, activate: false)
        return try XCTUnwrap(
            tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: index
            )
        )
    }

    private func makeFolderPin(
        _ tabManager: TabManager,
        in space: Space,
        folderId: UUID,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = tabManager.createNewTab(url: url, in: space, activate: false)
        return try XCTUnwrap(
            tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: folderId,
                at: index,
                openTargetFolder: false
            )
        )
    }

    private func makeEssentialPin(
        _ tabManager: TabManager,
        in space: Space,
        profileId: UUID,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = tabManager.createNewTab(url: url, in: space, activate: false)
        return try XCTUnwrap(
            tabManager.convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: index
            )
        )
    }

    private func topLevelPinnedItemIDs(_ tabManager: TabManager, in spaceId: UUID) -> [UUID] {
        tabManager.topLevelSpacePinnedItems(for: spaceId).map(\.id)
    }

    private func assertNonDisplayedRegularTabConversionCreatesLauncherOnly(
        target: ShortcutSectionTarget
    ) throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let tab = tabManager.createNewTab(url: "https://example.com/non-displayed-\(target.pathComponent)", in: space)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = nil
        let targetContainer = dragContainer(for: target, space: space, folder: folder)
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: targetContainer,
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
        XCTAssertNil(tabManager.tab(for: tab.id))
        let pin = try XCTUnwrap(shortcutPin(for: target, tabManager: tabManager, profileId: profileId, space: space, folder: folder))
        XCTAssertEqual(pin.launchURL, tab.url)
        XCTAssertNil(tabManager.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
    }

    private func assertLiveLauncherDropIntoRegularReusesLiveTab(
        source: ShortcutSectionTarget
    ) throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let pin = try makePin(
            source,
            tabManager: tabManager,
            space: space,
            folderId: folder.id,
            profileId: profileId,
            url: "https://example.com/live-\(source.pathComponent)"
        )
        let liveTab = tabManager.activateShortcutPin(pin, in: harness.windowState.id, currentSpaceId: space.id)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = pin.role
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: source.dropZone(spaceId: space.id, folderId: folder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: dragContainer(for: source, space: space, folder: folder),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertNil(shortcutPin(for: source, tabManager: tabManager, profileId: profileId, space: space, folder: folder))
        XCTAssertNil(tabManager.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        let converted = try XCTUnwrap(tabManager.tabsBySpace[space.id]?.first)
        XCTAssertTrue(converted === liveTab)
        XCTAssertEqual(converted.id, liveTab.id)
        XCTAssertNil(converted.shortcutPinId)
        XCTAssertNil(converted.shortcutPinRole)
        XCTAssertFalse(converted.isShortcutLiveInstance)
        XCTAssertEqual(converted.spaceId, space.id)
        XCTAssertNil(converted.folderId)
        XCTAssertEqual(harness.windowState.currentTabId, liveTab.id)
        XCTAssertNil(harness.windowState.currentShortcutPinId)
        XCTAssertNil(harness.windowState.currentShortcutPinRole)
        XCTAssertEqual(harness.windowState.activeTabForSpace[space.id], liveTab.id)
    }

    private func assertLauncherWithoutLiveShortcutDropIntoRegularCreatesNewTab(
        source: ShortcutSectionTarget
    ) throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let pin = try makePin(
            source,
            tabManager: tabManager,
            space: space,
            folderId: folder.id,
            profileId: profileId,
            url: "https://example.com/no-live-\(source.pathComponent)"
        )
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: source.dropZone(spaceId: space.id, folderId: folder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: dragContainer(for: source, space: space, folder: folder),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertNil(shortcutPin(for: source, tabManager: tabManager, profileId: profileId, space: space, folder: folder))
        XCTAssertNil(tabManager.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        let converted = try XCTUnwrap(tabManager.tabsBySpace[space.id]?.first)
        XCTAssertNotEqual(converted.id, pin.id)
        XCTAssertEqual(converted.url, pin.launchURL)
        XCTAssertNil(converted.shortcutPinId)
        XCTAssertFalse(converted.isShortcutLiveInstance)
        XCTAssertEqual(converted.spaceId, space.id)
        XCTAssertNil(converted.folderId)
    }

    private func assertLiveLauncherMovePreservesBinding(
        source: ShortcutSectionTarget,
        destination: ShortcutSectionTarget
    ) throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let sourceFolder = tabManager.createFolder(for: space.id, name: "Source")
        let destinationFolder = tabManager.createFolder(for: space.id, name: "Destination")
        let pin = try makePin(
            source,
            tabManager: tabManager,
            space: space,
            folderId: sourceFolder.id,
            profileId: profileId,
            url: "https://example.com/move-\(source.pathComponent)-\(destination.pathComponent)"
        )
        let liveTab = tabManager.activateShortcutPin(pin, in: harness.windowState.id, currentSpaceId: space.id)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = pin.role
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: source.dropZone(spaceId: space.id, folderId: sourceFolder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: dragContainer(for: source, space: space, folder: sourceFolder),
                toContainer: dragContainer(for: destination, space: space, folder: destinationFolder),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        let movedPin = try XCTUnwrap(shortcutPin(for: destination, tabManager: tabManager, profileId: profileId, space: space, folder: destinationFolder))
        XCTAssertEqual(movedPin.id, pin.id)
        let movedLiveTab = try XCTUnwrap(tabManager.shortcutLiveTab(for: movedPin.id, in: harness.windowState.id))
        XCTAssertTrue(movedLiveTab === liveTab)
        XCTAssertEqual(movedLiveTab.shortcutPinId, movedPin.id)
        XCTAssertEqual(movedLiveTab.shortcutPinRole, movedPin.role)
        XCTAssertTrue(movedLiveTab.isShortcutLiveInstance)
        XCTAssertEqual(movedLiveTab.spaceId, movedPin.spaceId)
        XCTAssertEqual(movedLiveTab.folderId, movedPin.folderId)
        XCTAssertEqual(harness.windowState.currentTabId, liveTab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, movedPin.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, movedPin.role)
    }

    private func makePin(
        _ target: ShortcutSectionTarget,
        tabManager: TabManager,
        space: Space,
        folderId: UUID,
        profileId: UUID,
        url: String
    ) throws -> ShortcutPin {
        switch target {
        case .spacePinned:
            return try makeSpacePinnedPin(tabManager, in: space, url: url, index: 0)
        case .folder:
            return try makeFolderPin(tabManager, in: space, folderId: folderId, url: url, index: 0)
        case .essentials:
            return try makeEssentialPin(tabManager, in: space, profileId: profileId, url: url, index: 0)
        }
    }

    private func dragContainer(
        for target: ShortcutSectionTarget,
        space: Space,
        folder: TabFolder
    ) -> TabDragManager.DragContainer {
        switch target {
        case .spacePinned:
            return .spacePinned(space.id)
        case .folder:
            return .folder(folder.id)
        case .essentials:
            return .essentials
        }
    }

    private func shortcutPin(
        for target: ShortcutSectionTarget,
        tabManager: TabManager,
        profileId: UUID,
        space: Space,
        folder: TabFolder
    ) -> ShortcutPin? {
        switch target {
        case .spacePinned:
            return tabManager.spacePinnedPins(for: space.id).first { $0.folderId == nil }
        case .folder:
            return tabManager.folderPinnedPins(for: folder.id, in: space.id).first
        case .essentials:
            return tabManager.essentialPins(for: profileId).first
        }
    }
}

private enum ShortcutSectionTarget: Equatable {
    case spacePinned
    case folder
    case essentials

    var pathComponent: String {
        switch self {
        case .spacePinned:
            return "space-pinned"
        case .folder:
            return "folder"
        case .essentials:
            return "essentials"
        }
    }

    func dropZone(spaceId: UUID, folderId: UUID) -> DropZoneID {
        switch self {
        case .spacePinned:
            return .spacePinned(spaceId)
        case .folder:
            return .folder(folderId)
        case .essentials:
            return .essentials
        }
    }
}

private struct LiveWindowHarness {
    let browserManager: BrowserManager
    let tabManager: TabManager
    let windowRegistry: WindowRegistry
    let windowState: BrowserWindowState
}
