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
}
