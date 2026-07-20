import XCTest

@testable import Sumi

@MainActor
final class SidebarURLDropServiceTests: XCTestCase {
    func testRegularDropUsesExactSpaceAndInsertionIndex() throws {
        let profileID = UUID()
        let space = Space(name: "Target", profileId: profileID)
        let harness = Harness(spaces: [space.id: space])
        let window = BrowserWindowState()

        XCTAssertTrue(harness.service.open(
            URL(string: "https://drop.example")!,
            in: window,
            atPresentedSlot: .spaceRegular(spaceId: space.id, slot: 3)
        ))

        let request = try XCTUnwrap(harness.tabOpening.requests.first)
        XCTAssertEqual(request.context.preferredSpaceId, space.id)
        XCTAssertEqual(request.context.regularInsertionIndex, 3)
        XCTAssertTrue(harness.shortcutInsertion.requests.isEmpty)
    }

    func testPinnedAndFolderDropsResolveExecutionProfileBeforeMutation() throws {
        let profileID = UUID()
        let space = Space(name: "Target", profileId: profileID)
        let folder = TabFolder(name: "Folder", spaceId: space.id)
        let harness = Harness(
            spaces: [space.id: space],
            folders: [folder.id: (folder, space)]
        )
        let window = BrowserWindowState()

        XCTAssertTrue(harness.service.open(
            URL(string: "https://pinned.example")!,
            in: window,
            atPresentedSlot: .spacePinned(spaceId: space.id, slot: 2)
        ))
        XCTAssertTrue(harness.service.open(
            URL(string: "https://folder.example")!,
            in: window,
            atPresentedSlot: .folder(folderId: folder.id, slot: 4)
        ))

        let pinned = try XCTUnwrap(harness.shortcutInsertion.requests.first?.placement)
        XCTAssertEqual(pinned.role, .spacePinned)
        XCTAssertEqual(pinned.executionProfileID, profileID)
        XCTAssertEqual(pinned.spaceID, space.id)
        XCTAssertNil(pinned.folderID)
        let folderPlacement = try XCTUnwrap(harness.shortcutInsertion.requests.last?.placement)
        XCTAssertEqual(folderPlacement.executionProfileID, profileID)
        XCTAssertEqual(folderPlacement.folderID, folder.id)
        XCTAssertFalse(folderPlacement.openTargetFolder)
    }

    func testIncognitoIgnoresPersistentDropSlot() {
        let harness = Harness()
        let window = BrowserWindowState()
        window.isIncognito = true

        XCTAssertTrue(harness.service.open(
            URL(string: "https://private.example")!,
            in: window,
            atPresentedSlot: .essentials(slot: 7)
        ))

        XCTAssertEqual(harness.tabOpening.requests.count, 1)
        XCTAssertIdentical(harness.tabOpening.requests.first?.context.windowState, window)
        XCTAssertTrue(harness.shortcutInsertion.requests.isEmpty)
    }

    func testNativeRegularDropUsesNativeSurfaceAndPersistentShortcutDropIsRejected() throws {
        let space = Space(name: "Target", profileId: UUID())
        let harness = Harness(spaces: [space.id: space])
        let window = BrowserWindowState()
        let settingsURL = try XCTUnwrap(URL(string: "sumi://settings?pane=privacy"))

        XCTAssertTrue(harness.service.open(
            settingsURL,
            in: window,
            atPresentedSlot: .spaceRegular(spaceId: space.id, slot: 1)
        ))
        XCTAssertFalse(harness.service.open(
            settingsURL,
            in: window,
            atPresentedSlot: .spacePinned(spaceId: space.id, slot: 1)
        ))

        XCTAssertEqual(harness.nativeSurfaces.requests.count, 1)
        XCTAssertEqual(harness.nativeSurfaces.requests.first?.preferredSpaceID, space.id)
        XCTAssertTrue(harness.tabOpening.requests.isEmpty)
        XCTAssertTrue(harness.shortcutInsertion.requests.isEmpty)
    }

    func testStaleDestinationAndEmptySlotMutateNothing() {
        let harness = Harness()
        let window = BrowserWindowState()
        let url = URL(string: "https://stale.example")!

        XCTAssertFalse(harness.service.open(
            url,
            in: window,
            atPresentedSlot: .spaceRegular(spaceId: UUID(), slot: 0)
        ))
        XCTAssertFalse(harness.service.open(
            url,
            in: window,
            atPresentedSlot: .empty
        ))

        XCTAssertTrue(harness.tabOpening.requests.isEmpty)
        XCTAssertTrue(harness.nativeSurfaces.requests.isEmpty)
        XCTAssertTrue(harness.shortcutInsertion.requests.isEmpty)
    }
}

@MainActor
private final class Harness {
    let tabOpening = DropTabOpening()
    let nativeSurfaces = DropNativeSurfaces()
    let destinations: DropDestinations
    let shortcutInsertion = DropShortcutInsertion()
    let service: SidebarURLDropService

    init(
        spaces: [UUID: Space] = [:],
        folders: [UUID: (folder: TabFolder, space: Space)] = [:]
    ) {
        let destinations = DropDestinations(spaces: spaces, folders: folders)
        self.destinations = destinations
        self.service = SidebarURLDropService(
            tabOpening: tabOpening,
            nativeSurfaces: nativeSurfaces,
            destinations: destinations,
            shortcutInsertion: shortcutInsertion
        )
    }
}

@MainActor
private final class DropTabOpening: URLTabOpening {
    struct Request { let url: String; let context: BrowserTabOpenContext }
    var requests: [Request] = []

    func openNewTab(url: String, context: BrowserTabOpenContext) -> Tab {
        requests.append(.init(url: url, context: context))
        return Tab(url: URL(string: url)!, loadsCachedFaviconOnInit: false)
    }
}

@MainActor
private final class DropNativeSurfaces: NativeBrowserSurfaceOpening {
    struct Request {
        let kind: SumiNativeBrowserSurfaceKind
        let url: URL
        let window: BrowserWindowState
        let preferredSpaceID: UUID?
    }
    var requests: [Request] = []

    func openNativeBrowserSurface(
        _ kind: SumiNativeBrowserSurfaceKind,
        url: URL,
        in windowState: BrowserWindowState,
        preferredSpaceId: UUID?
    ) {
        requests.append(.init(
            kind: kind,
            url: url,
            window: windowState,
            preferredSpaceID: preferredSpaceId
        ))
    }
}

@MainActor
private final class DropDestinations: SidebarURLDropDestinationResolving {
    let spaces: [UUID: Space]
    let folders: [UUID: (folder: TabFolder, space: Space)]
    var essentials: EssentialsShortcutPlacementOwner.InsertionPlan?

    init(
        spaces: [UUID: Space],
        folders: [UUID: (folder: TabFolder, space: Space)]
    ) {
        self.spaces = spaces
        self.folders = folders
    }

    func space(_ spaceID: UUID) -> Space? { spaces[spaceID] }
    func folder(_ folderID: UUID) -> (folder: TabFolder, space: Space)? {
        folders[folderID]
    }
    func essentialsInsertion(
        in windowState: BrowserWindowState,
        at index: Int
    ) -> EssentialsShortcutPlacementOwner.InsertionPlan? {
        essentials
    }
}

@MainActor
private final class DropShortcutInsertion: ShortcutURLInserting {
    struct Request {
        let url: URL
        let placement: ShortcutURLPlacement
        let window: BrowserWindowState
    }
    var requests: [Request] = []
    var result = true

    func insert(
        _ url: URL,
        placement: ShortcutURLPlacement,
        in windowState: BrowserWindowState
    ) -> Bool {
        requests.append(.init(url: url, placement: placement, window: windowState))
        return result
    }
}
