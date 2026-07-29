import AppKit
import Combine
import SumiDomain
import XCTest

@testable import Sumi

/// Shared fixtures and assertions for the sidebar drag/drop context tests.
/// The suites are split by concern but exercise one drag pipeline, so their
/// harness lives on a common base class instead of being duplicated per file.
struct LiveWindowHarness {
    let browserManager: BrowserManager
    let tabManager: BrowserManager
    let windowRegistry: WindowRegistry
    let windowState: BrowserWindowState
}

@MainActor
class SidebarDragContextTestCase: XCTestCase {
    func makeLiveWindowHarness() throws -> LiveWindowHarness {
        let container = try makeInMemoryStartupDatabase()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: container
            )
        )
        let windowRegistry = browserManager.windowRegistry
        let windowState = BrowserWindowState()
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        return LiveWindowHarness(
            browserManager: browserManager,
            tabManager: browserManager,
            windowRegistry: windowRegistry,
            windowState: windowState
        )
    }

    func makeScope(
        spaceId: UUID,
        profileId: UUID,
        sourceZone: DropZoneID,
        item: SumiDragItem,
        windowState: BrowserWindowState? = nil
    ) throws -> SidebarDragScope {
        let windowState = windowState ?? BrowserWindowState()
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

    func dragItem(_ tab: Tab) -> SumiDragItem {
        SumiDragItem(
            tabId: tab.id,
            title: tab.name,
            urlString: tab.url.absoluteString
        )
    }

    func dragItem(_ pin: ShortcutPin) -> SumiDragItem {
        SumiDragItem.shortcutPin(
            pin.id,
            title: pin.title,
            urlString: pin.launchURL.absoluteString
        )
    }

    func dragItem(_ folder: TabFolder) -> SumiDragItem {
        SumiDragItem.folder(folderId: folder.id, title: folder.name)
    }

    func makeSpace(
        _ browser: BrowserManager,
        name: String,
        profileId: UUID? = nil
    ) throws -> Space {
        if let profileId,
           browser.profileManager.profiles.contains(where: {
               $0.id == profileId
           }) == false {
            browser.profileManager.profiles.append(
                Profile(id: profileId, name: "Profile")
            )
        }
        return try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: name,
                icon: "square",
                profileID: profileId
            )
        )
    }

    func makeFolder(
        _ browser: BrowserManager,
        in spaceId: UUID,
        parentFolderId: UUID? = nil,
        name: String
    ) throws -> TabFolder {
        try XCTUnwrap(
            browser.sidebarFolderCommands.createFolder(
                in: spaceId,
                parentFolderID: parentFolderId,
                name: name
            )
        )
    }

    func makeSpacePinnedPin(
        _ tabManager: BrowserManager,
        in space: Space,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: url, in: space, activate: false)
        return try XCTUnwrap(
            tabManager.regularTabShortcutConversion.convert(
                tab,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: nil,
                    index: index,
                    opensFolder: false
                )
            )
        )
    }

    func makeFolderPin(
        _ tabManager: BrowserManager,
        in space: Space,
        folderId: UUID,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: url, in: space, activate: false)
        return try XCTUnwrap(
            tabManager.regularTabShortcutConversion.convert(
                tab,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: folderId,
                    index: index,
                    opensFolder: false
                )
            )
        )
    }

    func makeEssentialPin(
        _ tabManager: BrowserManager,
        in space: Space,
        profileId: UUID,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: url, in: space, activate: false)
        return try XCTUnwrap(
            tabManager.regularTabShortcutConversion.convert(
                tab,
                destination: TabShortcutPinDestination(
                    role: .essential,
                    profileId: profileId,
                    spaceId: nil,
                    folderId: nil,
                    index: index,
                    opensFolder: false
                )
            )
        )
    }

    func topLevelPinnedItemIDs(_ tabManager: BrowserManager, in spaceId: UUID) -> [UUID] {
        tabManager.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: spaceId).map(\.id)
    }

    func assertNonDisplayedRegularTabConversionCreatesLauncherOnly(
        target: ShortcutSectionTarget
    ) throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/non-displayed-\(target.pathComponent)", in: space)
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

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: targetContainer,
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: tab.id))
        let pin = try XCTUnwrap(shortcutPin(for: target, tabManager: tabManager, profileId: profileId, space: space, folder: folder))
        XCTAssertEqual(pin.launchURL, tab.url)
        XCTAssertNil(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
    }

    func assertLiveLauncherDropIntoRegularReusesLiveTab(
        source: ShortcutSectionTarget
    ) throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let pin = try makePin(
            source,
            tabManager: tabManager,
            space: space,
            folderId: folder.id,
            profileId: profileId,
            url: "https://example.com/live-\(source.pathComponent)"
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(pin, in: harness.windowState.id, currentSpaceId: space.id)!
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = pin.role
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: source.dropZone(spaceId: space.id, folderId: folder.id),
            item: dragItem(pin),
            windowState: harness.windowState
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: dragContainer(for: source, space: space, folder: folder),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        let persistedPin = shortcutPin(
            for: source,
            tabManager: tabManager,
            profileId: profileId,
            space: space,
            folder: folder
        )
        XCTAssertNil(persistedPin)
        XCTAssertNil(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        let converted = try XCTUnwrap(tabManager.regularTabCollectionOwner.tabs(in: space.id).first)
        XCTAssertIdentical(converted, liveTab)
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

    func assertLauncherWithoutLiveShortcutDropIntoRegularCreatesNewTab(
        source: ShortcutSectionTarget
    ) throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
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

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: dragContainer(for: source, space: space, folder: folder),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        let persistedPin = shortcutPin(
            for: source,
            tabManager: tabManager,
            profileId: profileId,
            space: space,
            folder: folder
        )
        XCTAssertNil(persistedPin)
        XCTAssertNil(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        let converted = try XCTUnwrap(tabManager.regularTabCollectionOwner.tabs(in: space.id).first)
        XCTAssertNotEqual(converted.id, pin.id)
        XCTAssertEqual(converted.url, pin.launchURL)
        XCTAssertNil(converted.shortcutPinId)
        XCTAssertFalse(converted.isShortcutLiveInstance)
        XCTAssertEqual(converted.spaceId, space.id)
        XCTAssertNil(converted.folderId)
    }

    func assertLiveLauncherMovePreservesBinding(
        source: ShortcutSectionTarget,
        destination: ShortcutSectionTarget
    ) throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let sourceFolder = try makeFolder(tabManager, in: space.id, name: "Source")
        let destinationFolder = try makeFolder(tabManager, in: space.id, name: "Destination")
        let pin = try makePin(
            source,
            tabManager: tabManager,
            space: space,
            folderId: sourceFolder.id,
            profileId: profileId,
            url: "https://example.com/move-\(source.pathComponent)-\(destination.pathComponent)"
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(pin, in: harness.windowState.id, currentSpaceId: space.id)!
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = pin.role
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: source.dropZone(spaceId: space.id, folderId: sourceFolder.id),
            item: dragItem(pin),
            windowState: harness.windowState
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
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
        let movedLiveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: movedPin.id, in: harness.windowState.id))
        XCTAssertIdentical(movedLiveTab, liveTab)
        XCTAssertEqual(movedLiveTab.shortcutPinId, movedPin.id)
        XCTAssertEqual(movedLiveTab.shortcutPinRole, movedPin.role)
        XCTAssertTrue(movedLiveTab.isShortcutLiveInstance)
        XCTAssertEqual(movedLiveTab.spaceId, movedPin.spaceId)
        XCTAssertEqual(movedLiveTab.folderId, movedPin.folderId)
        XCTAssertEqual(harness.windowState.currentTabId, liveTab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, movedPin.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, movedPin.role)
    }

    func present(_ slot: DropZoneSlot, in state: SidebarDragState) {
        state.presentDropResolution(
            SidebarDropResolution(
                slot: slot,
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        )
    }

    func makePin(
        _ target: ShortcutSectionTarget,
        tabManager: BrowserManager,
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

    func emptyPreviewAsset(size: CGSize) -> SidebarDragPreviewAsset {
        SidebarDragPreviewAsset(
            image: NSImage(size: size),
            size: size,
            anchorOffset: CGPoint(x: size.width / 2, y: size.height / 2)
        )
    }

    func dragContainer(
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

    func shortcutPin(
        for target: ShortcutSectionTarget,
        tabManager: BrowserManager,
        profileId: UUID,
        space: Space,
        folder: TabFolder
    ) -> ShortcutPin? {
        switch target {
        case .spacePinned:
            return tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).first { $0.folderId == nil }
        case .folder:
            return tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).first
        case .essentials:
            return tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).first
        }
    }
}

enum ShortcutSectionTarget: Equatable {
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
