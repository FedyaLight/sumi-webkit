import AppKit
import XCTest

@testable import Sumi

@MainActor
final class SidebarDropCoordinatorBoundaryTests: XCTestCase {
    func testSameContainerReorderAdjustsIndexAfterSourceRemoval() {
        let sourceId = UUID()
        let spaceId = UUID()
        let profileId = UUID()
        let pin = ShortcutPin(
            id: sourceId,
            role: .essential,
            profileId: profileId,
            index: 0,
            launchURL: URL(string: "https://source.example")!,
            title: "Source"
        )
        let inventory = StubInventory(
            identities: [
                .pin(sourceId),
                .pin(UUID()),
                .pin(UUID()),
                .pin(UUID()),
            ]
        )
        let operations = RecordingDragOperations(payload: .pin(pin))
        let pasteboard = makePasteboard(
            item: SumiDragItem.shortcutPin(sourceId, title: "Source"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: spaceId,
                profileId: profileId,
                sourceContainer: .essentials,
                sourceItemId: sourceId,
                sourceItemKind: .tab
            )
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = spaceId
        windowState.currentProfileId = profileId

        XCTAssertTrue(
            SidebarDropCoordinator.performDrop(
                pasteboard: pasteboard,
                resolution: SidebarDropResolution(
                    slot: .essentials(slot: 2),
                    folderIntent: .none,
                    activeHoveredFolderId: nil
                ),
                sourceInventory: inventory,
                dragOperations: operations,
                urlDropService: unusedURLDropService(),
                windowState: windowState
            )
        )

        let operation = try! XCTUnwrap(operations.performed.first)
        // Visual slot 2 with source at 0 → model insertion index 3.
        XCTAssertEqual(operation.toIndex, 3)
        XCTAssertEqual(operation.fromContainer, .essentials)
        XCTAssertEqual(operation.toContainer, .essentials)
    }

    func testCrossContainerDropSkipsSameContainerAdjustment() {
        let sourceId = UUID()
        let spaceId = UUID()
        let profileId = UUID()
        let pin = ShortcutPin(
            id: sourceId,
            role: .essential,
            profileId: profileId,
            index: 0,
            launchURL: URL(string: "https://source.example")!,
            title: "Source"
        )
        let inventory = StubInventory(
            identities: [
                .pin(sourceId),
                .pin(UUID()),
                .pin(UUID()),
            ]
        )
        let operations = RecordingDragOperations(payload: .pin(pin))
        let pasteboard = makePasteboard(
            item: SumiDragItem.shortcutPin(sourceId, title: "Source"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: spaceId,
                profileId: profileId,
                sourceContainer: .essentials,
                sourceItemId: sourceId,
                sourceItemKind: .tab
            )
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = spaceId
        windowState.currentProfileId = profileId

        XCTAssertTrue(
            SidebarDropCoordinator.performDrop(
                pasteboard: pasteboard,
                resolution: SidebarDropResolution(
                    slot: .spacePinned(spaceId: spaceId, slot: 2),
                    folderIntent: .none,
                    activeHoveredFolderId: nil
                ),
                sourceInventory: inventory,
                dragOperations: operations,
                urlDropService: unusedURLDropService(),
                windowState: windowState
            )
        )

        let operation = try! XCTUnwrap(operations.performed.first)
        XCTAssertEqual(operation.toIndex, 2)
        XCTAssertEqual(operation.fromContainer, .essentials)
        XCTAssertEqual(operation.toContainer, .spacePinned(spaceId))
    }

    func testInvalidOrStaleScopeDoesNotMutate() {
        let sourceId = UUID()
        let operations = RecordingDragOperations(
            payload: .pin(
                ShortcutPin(
                    id: sourceId,
                    role: .essential,
                    profileId: UUID(),
                    index: 0,
                    launchURL: URL(string: "https://source.example")!,
                    title: "Source"
                )
            )
        )
        let pasteboard = makePasteboard(
            item: SumiDragItem.shortcutPin(sourceId, title: "Source"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: UUID(),
                profileId: UUID(),
                sourceContainer: .essentials,
                sourceItemId: sourceId,
                sourceItemKind: .tab
            )
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = UUID()
        windowState.currentProfileId = UUID()

        XCTAssertFalse(
            SidebarDropCoordinator.performDrop(
                pasteboard: pasteboard,
                resolution: SidebarDropResolution(
                    slot: .essentials(slot: 1),
                    folderIntent: .none,
                    activeHoveredFolderId: nil
                ),
                sourceInventory: StubInventory(identities: [.pin(sourceId)]),
                dragOperations: operations,
                urlDropService: unusedURLDropService(),
                windowState: windowState
            )
        )
        XCTAssertTrue(operations.performed.isEmpty)
        XCTAssertTrue(operations.resolvedItems.isEmpty)
    }

    func testEmptySlotDoesNotMutate() {
        let operations = RecordingDragOperations(payload: nil)
        XCTAssertFalse(
            SidebarDropCoordinator.performDrop(
                pasteboard: NSPasteboard(name: NSPasteboard.Name("SumiEmptyDrop-\(UUID())")),
                resolution: SidebarDropResolution(
                    slot: .empty,
                    folderIntent: .none,
                    activeHoveredFolderId: nil
                ),
                sourceInventory: StubInventory(identities: []),
                dragOperations: operations,
                urlDropService: unusedURLDropService(),
                windowState: BrowserWindowState()
            )
        )
        XCTAssertTrue(operations.performed.isEmpty)
    }

    func testURLDropDoesNotDependOnDragInventory() {
        let space = Space(name: "Target", profileId: UUID())
        let urlHarness = URLDropHarness(spaces: [space.id: space])
        let inventory = FailingInventory()
        let operations = RecordingDragOperations(payload: nil)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SumiURLDrop-\(UUID())"))
        pasteboard.clearContents()
        pasteboard.setString("https://drop.example", forType: .URL)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id

        XCTAssertTrue(
            SidebarDropCoordinator.performDrop(
                pasteboard: pasteboard,
                resolution: SidebarDropResolution(
                    slot: .spaceRegular(spaceId: space.id, slot: 4),
                    folderIntent: .none,
                    activeHoveredFolderId: nil
                ),
                sourceInventory: inventory,
                dragOperations: operations,
                urlDropService: urlHarness.service,
                windowState: windowState
            )
        )

        XCTAssertTrue(operations.performed.isEmpty)
        XCTAssertEqual(urlHarness.tabOpening.requests.count, 1)
        XCTAssertEqual(urlHarness.tabOpening.requests.first?.context.regularInsertionIndex, 4)
        XCTAssertFalse(inventory.wasQueried)
    }

    func testTransactionPortRejectsStaleWindowBeforeReadingDragReceipt() {
        let windowID = UUID()
        let staleWindow = BrowserWindowState(id: windowID)
        let replacementWindow = BrowserWindowState(id: windowID)
        let registry = WindowRegistry()
        registry.register(staleWindow)
        registry.unregister(windowID)
        registry.register(replacementWindow)
        let inventory = FailingInventory()
        let operations = RecordingDragOperations(payload: nil)
        let port = SidebarDragTransactionPort(
            windows: SidebarWindowIdentityQuery(registry: registry),
            sourceInventory: inventory,
            dragOperations: operations,
            urlDropService: unusedURLDropService()
        )

        XCTAssertFalse(
            port.commit(
                pasteboard: NSPasteboard(
                    name: NSPasteboard.Name("SumiStaleDrop-\(windowID)")
                ),
                resolution: SidebarDropResolution(
                    slot: .spaceRegular(spaceId: UUID(), slot: 0),
                    folderIntent: .none,
                    activeHoveredFolderId: nil
                ),
                windowState: staleWindow
            )
        )
        XCTAssertFalse(inventory.wasQueried)
        XCTAssertTrue(operations.resolvedItems.isEmpty)
        XCTAssertTrue(operations.performed.isEmpty)
    }

    func testLiveCoordinatorCompositionExecutesWithoutBrowserManagerReachThrough() throws {
        let profile = Profile(name: "Sidebar Drop Composition")
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        let space = try XCTUnwrap(
            browserManager.sidebarSpaceLifecycle.createSpace(
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profile.id
            )
        )
        let first = try makeEssentialPin(
            browserManager,
            in: space,
            profileId: profile.id,
            url: "https://first.example",
            index: 0
        )
        let moved = try makeEssentialPin(
            browserManager,
            in: space,
            profileId: profile.id,
            url: "https://moved.example",
            index: 1
        )
        let pasteboard = makePasteboard(
            item: SumiDragItem.shortcutPin(moved.id, title: "Moved"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .essentials,
                sourceItemId: moved.id,
                sourceItemKind: .tab
            )
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        browserManager.windowRegistry.register(windowState)
        let context = WindowSidebarContext.make(
            browserManager: browserManager,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )

        XCTAssertTrue(
            context.dragTransactions.commit(
                pasteboard: pasteboard,
                resolution: SidebarDropResolution(
                    slot: .essentials(slot: 0),
                    folderIntent: .none,
                    activeHoveredFolderId: nil
                ),
                windowState: windowState
            )
        )
        XCTAssertEqual(
            browserManager.shortcutPinCollectionStateOwner
                .essentialPins(for: profile.id).map(\.id),
            [moved.id, first.id]
        )
    }

    func testOperationIndexProjectionPreservesSameAndCrossContainerSemantics() {
        XCTAssertEqual(
            SidebarDropProjection.operationIndex(
                visualIndex: 2,
                sourceContainer: .essentials,
                targetContainer: .essentials,
                sourceIndex: 0,
                sourceItemCount: 4
            ),
            3
        )
        XCTAssertEqual(
            SidebarDropProjection.operationIndex(
                visualIndex: 2,
                sourceContainer: .essentials,
                targetContainer: .spacePinned(UUID()),
                sourceIndex: 0,
                sourceItemCount: 4
            ),
            2
        )
        XCTAssertEqual(
            SidebarDropProjection.operationIndex(
                visualIndex: 99,
                sourceContainer: .essentials,
                targetContainer: .essentials,
                sourceIndex: 1,
                sourceItemCount: 3
            ),
            3
        )
    }

    private func makePasteboard(
        item: SumiDragItem,
        scope: SidebarDragScope
    ) -> NSPasteboard {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("SumiDropBoundary-\(item.stableID)")
        )
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item.pasteboardItem(scope: scope)]))
        return pasteboard
    }

    private func unusedURLDropService() -> SidebarURLDropService {
        URLDropHarness().service
    }

    private func makeEssentialPin(
        _ browser: BrowserManager,
        in space: Space,
        profileId: UUID,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = browser.regularTabLifecycleOwner.createNewTab(
            url: url,
            in: space,
            activate: false
        )
        return try XCTUnwrap(
            browser.regularTabShortcutConversion.convert(
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
}

@MainActor
private final class StubInventory: SidebarDragSourceInventorying {
    let identities: [SidebarDragSourceIdentity]

    init(identities: [SidebarDragSourceIdentity]) {
        self.identities = identities
    }

    func sourceIdentities(for scope: SidebarDragScope) -> [SidebarDragSourceIdentity]? {
        switch scope.sourceContainer {
        case .none:
            return nil
        default:
            return identities
        }
    }
}

@MainActor
private final class FailingInventory: SidebarDragSourceInventorying {
    private(set) var wasQueried = false

    func sourceIdentities(for scope: SidebarDragScope) -> [SidebarDragSourceIdentity]? {
        wasQueried = true
        XCTFail("URL drop must not query drag source inventory")
        return nil
    }
}

@MainActor
private final class RecordingDragOperations: SidebarDragOperationExecuting {
    var payload: DragOperation.Payload?
    private(set) var resolvedItems: [SumiDragItem] = []
    private(set) var performed: [DragOperation] = []

    init(payload: DragOperation.Payload?) {
        self.payload = payload
    }

    func resolveSidebarDragPayload(for item: SumiDragItem) -> DragOperation.Payload? {
        resolvedItems.append(item)
        return payload
    }

    func performSidebarDragOperation(_ operation: DragOperation) -> Bool {
        performed.append(operation)
        return true
    }
}

@MainActor
private final class URLDropHarness {
    let tabOpening = URLDropTabOpening()
    let nativeSurfaces = URLDropNativeSurfaces()
    let destinations: URLDropDestinations
    let shortcutInsertion = URLDropShortcutInsertion()
    let service: SidebarURLDropService

    init(spaces: [UUID: Space] = [:]) {
        let destinations = URLDropDestinations(spaces: spaces)
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
private final class URLDropTabOpening: URLTabOpening {
    struct Request { let url: String; let context: BrowserTabOpenContext }
    var requests: [Request] = []

    func openNewTab(url: String, context: BrowserTabOpenContext) -> Tab {
        requests.append(Request(url: url, context: context))
        return Tab(url: URL(string: url)!, loadsCachedFaviconOnInit: false)
    }
}

@MainActor
private final class URLDropNativeSurfaces: NativeBrowserSurfaceOpening {
    func openNativeBrowserSurface(
        _ kind: SumiNativeBrowserSurfaceKind,
        url: URL,
        in windowState: BrowserWindowState,
        preferredSpaceId: UUID?
    ) {}
}

@MainActor
private final class URLDropDestinations: SidebarURLDropDestinationResolving {
    let spaces: [UUID: Space]

    init(spaces: [UUID: Space]) {
        self.spaces = spaces
    }

    func space(_ spaceID: UUID) -> Space? { spaces[spaceID] }
    func folder(_ folderID: UUID) -> (folder: TabFolder, space: Space)? { nil }
    func essentialsInsertion(
        in windowState: BrowserWindowState,
        at index: Int
    ) -> EssentialsShortcutPlacementOwner.InsertionPlan? { nil }
}

@MainActor
private final class URLDropShortcutInsertion: ShortcutURLInserting {
    func insert(
        _ url: URL,
        placement: ShortcutURLPlacement,
        in windowState: BrowserWindowState
    ) -> Bool {
        false
    }
}
