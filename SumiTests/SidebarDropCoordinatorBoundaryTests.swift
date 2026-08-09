import AppKit
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SidebarDropCoordinatorBoundaryTests: XCTestCase {
    func testCommitUsesTheGapAlreadyPresentedToTheUser() {
        let spaceID = UUID()
        let state = SidebarDragState()
        let presented = SidebarDropResolution(
            slot: .spacePinned(spaceId: spaceID, slot: 2),
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
        state.presentDropResolution(presented)
        var refreshCount = 0

        let committed = state.beginDropCommit(
            refreshingIfEmpty: {
                refreshCount += 1
                return SidebarDropResolution(
                    slot: .spacePinned(spaceId: spaceID, slot: 1),
                    folderIntent: .none,
                    activeHoveredFolderId: nil
                )
            }
        )

        XCTAssertEqual(committed, presented)
        XCTAssertEqual(refreshCount, 0)
    }

    func testSameContainerCommitKeepsPresentedVisualIndex() {
        let sourceId = UUID()
        let spaceId = UUID()
        let profileId = UUID()
        let pin = ShortcutPin(
            id: sourceId,
            role: .favorite,
            profileId: profileId,
            index: 0,
            launchURL: URL(string: "https://source.example")!,
            title: "Source"
        )
        let operations = RecordingDragOperations(payload: .pin(pin))
        let pasteboard = makePasteboard(
            item: SumiDragItem.shortcutPin(sourceId, title: "Source"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: spaceId,
                profileId: profileId,
                sourceContainer: .favorite,
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
                    slot: .favorite(slot: 2),
                    folderIntent: .none,
                    activeHoveredFolderId: nil
                ),
                dragOperations: operations,
                urlDropService: unusedURLDropService(),
                windowState: windowState
            )
        )

        let intent = try! XCTUnwrap(operations.performed.first)
        XCTAssertEqual(intent.presentedVisualIndex, 2)
        XCTAssertEqual(intent.fromContainer, .favorite)
        XCTAssertEqual(intent.toContainer, .favorite)
    }

    func testCrossContainerDropSkipsSameContainerAdjustment() {
        let sourceId = UUID()
        let spaceId = UUID()
        let profileId = UUID()
        let pin = ShortcutPin(
            id: sourceId,
            role: .favorite,
            profileId: profileId,
            index: 0,
            launchURL: URL(string: "https://source.example")!,
            title: "Source"
        )
        let operations = RecordingDragOperations(payload: .pin(pin))
        let pasteboard = makePasteboard(
            item: SumiDragItem.shortcutPin(sourceId, title: "Source"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: spaceId,
                profileId: profileId,
                sourceContainer: .favorite,
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
                dragOperations: operations,
                urlDropService: unusedURLDropService(),
                windowState: windowState
            )
        )

        let intent = try! XCTUnwrap(operations.performed.first)
        XCTAssertEqual(intent.presentedVisualIndex, 2)
        XCTAssertEqual(intent.fromContainer, .favorite)
        XCTAssertEqual(intent.toContainer, .spacePinned(spaceId))
    }

    func testPairingTargetCommitsThroughSplitBoundaryInsteadOfReorder() {
        let sourceID = UUID()
        let targetID = SplitMemberID.regularTab(UUID())
        let spaceID = UUID()
        let profileID = UUID()
        let sourceTab = Tab(
            id: sourceID,
            url: URL(string: "https://source.example")!,
            loadsCachedFaviconOnInit: false
        )
        let operations = RecordingDragOperations(payload: .tab(sourceTab))
        let pairing = RecordingSplitPairing()
        let pasteboard = makePasteboard(
            item: SumiDragItem(tabId: sourceID, title: "Source"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: spaceID,
                profileId: profileID,
                sourceContainer: .spaceRegular(spaceID),
                sourceItemId: sourceID,
                sourceItemKind: .tab
            )
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = spaceID
        windowState.currentProfileId = profileID
        let target = SidebarSplitPairingTarget(
            memberID: targetID,
            side: .right,
            rect: CGRect(x: 20, y: 30, width: 80, height: 28),
            presentation: .projectedPair(
                companionRect: CGRect(x: 10, y: 30, width: 80, height: 28)
            )
        )

        XCTAssertTrue(
            SidebarDropCoordinator.performDrop(
                pasteboard: pasteboard,
                resolution: SidebarDropResolution(
                    slot: .spaceRegular(spaceId: spaceID, slot: 2),
                    folderIntent: .none,
                    activeHoveredFolderId: nil,
                    splitPairingTarget: target
                ),
                dragOperations: operations,
                urlDropService: unusedURLDropService(),
                splitPairing: pairing,
                windowState: windowState
            )
        )
        XCTAssertEqual(pairing.targets, [target])
        XCTAssertTrue(operations.performed.isEmpty)
    }

    func testPinnedRowSlotPassesThroughStorageProjectionUnchanged() {
        let sourceId = UUID()
        let spaceId = UUID()
        let profileId = UUID()
        let pin = ShortcutPin(
            id: sourceId,
            role: .spacePinned,
            profileId: profileId,
            index: 0,
            launchURL: URL(string: "https://source.example")!,
            title: "Source"
        )
        let operations = RecordingDragOperations(payload: .pin(pin))
        let pasteboard = makePasteboard(
            item: SumiDragItem.shortcutPin(sourceId, title: "Source"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: spaceId,
                profileId: profileId,
                sourceContainer: .spacePinned(spaceId),
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
                    slot: .spacePinned(spaceId: spaceId, slot: 3),
                    folderIntent: .none,
                    activeHoveredFolderId: nil
                ),
                dragOperations: operations,
                urlDropService: unusedURLDropService(),
                windowState: windowState
            )
        )

        let intent = try! XCTUnwrap(operations.performed.first)
        XCTAssertEqual(intent.presentedVisualIndex, 3)
        XCTAssertEqual(intent.fromContainer, .spacePinned(spaceId))
        XCTAssertEqual(intent.toContainer, .spacePinned(spaceId))
    }

    func testInvalidOrStaleScopeDoesNotMutate() {
        let sourceId = UUID()
        let operations = RecordingDragOperations(
            payload: .pin(
                ShortcutPin(
                    id: sourceId,
                    role: .favorite,
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
                sourceContainer: .favorite,
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
                    slot: .favorite(slot: 1),
                    folderIntent: .none,
                    activeHoveredFolderId: nil
                ),
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
                dragOperations: operations,
                urlDropService: unusedURLDropService(),
                windowState: BrowserWindowState()
            )
        )
        XCTAssertTrue(operations.performed.isEmpty)
    }

    func testURLDropBypassesDragPayloadResolution() {
        let space = Space(name: "Target", profileId: UUID())
        let urlHarness = URLDropHarness(spaces: [space.id: space])
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
                dragOperations: operations,
                urlDropService: urlHarness.service,
                windowState: windowState
            )
        )

        XCTAssertTrue(operations.performed.isEmpty)
        XCTAssertEqual(urlHarness.tabOpening.requests.count, 1)
        XCTAssertEqual(urlHarness.tabOpening.requests.first?.context.regularInsertionIndex, 4)
    }

    func testTransactionPortRejectsStaleWindowBeforeReadingDragReceipt() {
        let windowID = UUID()
        let staleWindow = BrowserWindowState(id: windowID)
        let replacementWindow = BrowserWindowState(id: windowID)
        let registry = WindowRegistry()
        registry.register(staleWindow)
        registry.unregister(windowID)
        registry.register(replacementWindow)
        let operations = RecordingDragOperations(payload: nil)
        let port = SidebarDragTransactionPort(
            windows: SidebarWindowIdentityQuery(registry: registry),
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
        let first = try makeFavoritePin(
            browserManager,
            in: space,
            profileId: profile.id,
            url: "https://first.example",
            index: 0
        )
        let moved = try makeFavoritePin(
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
                sourceContainer: .favorite,
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
                    slot: .favorite(slot: 0),
                    folderIntent: .none,
                    activeHoveredFolderId: nil
                ),
                windowState: windowState
            )
        )
        XCTAssertEqual(
            browserManager.shortcutPinCollectionStateOwner
                .favoritePins(for: profile.id).map(\.id),
            [moved.id, first.id]
        )
    }

    func testLiveSidebarPairingCreatesRegularSplitThroughExistingDropService() throws {
        let profile = Profile(name: "Sidebar Pairing")
        let browser = makeSafariExtensionTestBrowserManager(profile: profile)
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profile.id
            )
        )
        let targetTab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://target.example",
            in: space,
            activate: false
        )
        let sourceTab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example",
            in: space,
            activate: false
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        browser.windowRegistry.register(windowState)
        let context = WindowSidebarContext.make(
            browserManager: browser,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )
        let pasteboard = makePasteboard(
            item: SumiDragItem(tabId: sourceTab.id, title: sourceTab.name),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .spaceRegular(space.id),
                sourceItemId: sourceTab.id,
                sourceItemKind: .tab
            )
        )

        XCTAssertTrue(
            context.dragTransactions.commit(
                pasteboard: pasteboard,
                resolution: SidebarDropResolution(
                    slot: .spaceRegular(spaceId: space.id, slot: 1),
                    folderIntent: .none,
                    activeHoveredFolderId: nil,
                    splitPairingTarget: SidebarSplitPairingTarget(
                        memberID: .regularTab(targetTab.id),
                        side: .right,
                        rect: CGRect(x: 105, y: 20, width: 87, height: 28),
                        presentation: .projectedPair(
                            companionRect: CGRect(
                                x: 12,
                                y: 20,
                                width: 87,
                                height: 28
                            )
                        )
                    )
                ),
                windowState: windowState
            )
        )

        let group = try XCTUnwrap(
            browser.splitGroupStore.group(
                containing: .regularTab(targetTab.id)
            )
        )
        XCTAssertEqual(
            group.memberIDs,
            [.regularTab(targetTab.id), .regularTab(sourceTab.id)]
        )
        XCTAssertEqual(group.container, .regularTabs(spaceId: space.id))
    }

    func testFavoriteCommitMatchesPresentedVisualGapWhenSplitTileIsPresent() throws {
        let profile = Profile(name: "Favorite Split Reorder")
        let browser = makeSafariExtensionTestBrowserManager(profile: profile)
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profile.id
            )
        )
        let pins = try (0..<4).map { index in
            try makeFavoritePin(
                browser,
                in: space,
                profileId: profile.id,
                url: "https://favorite-\(index).example",
                index: index
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: pins.prefix(2).map { .shortcutPin($0.id) },
            layoutKind: .horizontal,
            container: .favoriteSidebar(profileId: profile.id, index: 0)
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.favoriteItems(for: profile.id),
            [.splitGroup(group.id), .shortcut(pins[2].id), .shortcut(pins[3].id)]
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        browser.windowRegistry.register(windowState)
        let pasteboard = makePasteboard(
            item: SumiDragItem.shortcutPin(pins[2].id, title: "Moved"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .favorite,
                sourceItemId: pins[2].id,
                sourceItemKind: .tab
            )
        )
        let context = WindowSidebarContext.make(
            browserManager: browser,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )

        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: pasteboard,
            resolution: SidebarDropResolution(
                slot: .favorite(slot: 2),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.favoriteItems(for: profile.id),
            [.splitGroup(group.id), .shortcut(pins[3].id), .shortcut(pins[2].id)]
        )
    }

    func testFavoriteCommitKeepsPinAndSplitMovesAlignedWithPresentedGap() throws {
        let profile = Profile(name: "Favorite Mixed Reorder")
        let browser = makeSafariExtensionTestBrowserManager(profile: profile)
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profile.id
            )
        )
        let pins = try (0..<4).map { index in
            try makeFavoritePin(
                browser,
                in: space,
                profileId: profile.id,
                url: "https://mixed-favorite-\(index).example",
                index: index
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: pins[1...2].map { .shortcutPin($0.id) },
            layoutKind: .vertical,
            container: .favoriteSidebar(profileId: profile.id, index: 1)
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        browser.windowRegistry.register(windowState)
        let context = WindowSidebarContext.make(
            browserManager: browser,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )
        let trailingPinPasteboard = makePasteboard(
            item: SumiDragItem.shortcutPin(pins[3].id, title: "Trailing"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .favorite,
                sourceItemId: pins[3].id,
                sourceItemKind: .tab
            )
        )

        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: trailingPinPasteboard,
            resolution: SidebarDropResolution(
                slot: .favorite(slot: 0),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.favoriteItems(for: profile.id),
            [.shortcut(pins[3].id), .shortcut(pins[0].id), .splitGroup(group.id)]
        )
        XCTAssertEqual(
            browser.splitGroupStore.group(id: group.id)?.container,
            .favoriteSidebar(profileId: profile.id, index: 2)
        )

        let splitPasteboard = makePasteboard(
            item: SumiDragItem.splitGroup(group.id, title: "Split"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .favorite,
                sourceItemId: group.id,
                sourceItemKind: .splitGroup
            )
        )
        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: splitPasteboard,
            resolution: SidebarDropResolution(
                slot: .favorite(slot: 0),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.favoriteItems(for: profile.id),
            [.splitGroup(group.id), .shortcut(pins[3].id), .shortcut(pins[0].id)]
        )
        XCTAssertEqual(
            browser.splitGroupStore.group(id: group.id)?.container,
            .favoriteSidebar(profileId: profile.id, index: 0)
        )
    }

    func testLiveCoordinatorMovesFavoriteSplitGroupIntoPinnedGap() throws {
        let profile = Profile(name: "Favorite Split Drop")
        let browser = makeSafariExtensionTestBrowserManager(profile: profile)
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profile.id
            )
        )
        let pins = try (0..<2).map { index in
            try makeFavoritePin(
                browser,
                in: space,
                profileId: profile.id,
                url: "https://split-\(index).example",
                index: index
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: pins.map { .shortcutPin($0.id) },
            layoutKind: .vertical,
            container: .favoriteSidebar(profileId: profile.id, index: 0)
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        browser.windowRegistry.register(windowState)
        let item = SumiDragItem.splitGroup(group.id, title: "Split View")
        let pasteboard = makePasteboard(
            item: item,
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .favorite,
                sourceItemId: group.id,
                sourceItemKind: .splitGroup
            )
        )
        let context = WindowSidebarContext.make(
            browserManager: browser,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )

        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: pasteboard,
            resolution: SidebarDropResolution(
                slot: .spacePinned(spaceId: space.id, slot: 0),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))

        let movedGroup = try XCTUnwrap(browser.splitGroupStore.group(id: group.id))
        XCTAssertEqual(
            movedGroup.container,
            .shortcutSidebar(
                spaceId: space.id,
                profileId: profile.id,
                folderId: nil,
                index: 0
            )
        )
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [.splitGroup(group.id)]
        )
    }

    func testRegularSplitGroupDropAtItsPresentedTrailingBoundaryIsNoOp() throws {
        let profile = Profile(name: "Regular Split Boundary")
        let browser = makeSafariExtensionTestBrowserManager(profile: profile)
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profile.id
            )
        )
        let tabs = (0..<4).map { index in
            browser.regularTabLifecycleOwner.createNewTab(
                url: "https://regular-boundary-\(index).example",
                in: space,
                activate: false
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .regularTab(tabs[1].id),
                .regularTab(tabs[2].id),
            ],
            layoutKind: .horizontal,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        browser.windowRegistry.register(windowState)
        let context = WindowSidebarContext.make(
            browserManager: browser,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )
        let pasteboard = makePasteboard(
            item: SumiDragItem.splitGroup(group.id, title: "Split"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .spaceRegular(space.id),
                sourceItemId: group.id,
                sourceItemKind: .splitGroup
            )
        )

        // The boundary after [split(tab 1, tab 2)] is visual slot 2. Storage
        // projection happens only when the drop commits.
        XCTAssertFalse(context.dragTransactions.commit(
            pasteboard: pasteboard,
            resolution: SidebarDropResolution(
                slot: .spaceRegular(spaceId: space.id, slot: 2),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        XCTAssertEqual(
            browser.regularTabCollectionOwner.tabs(in: space.id).map(\.id),
            tabs.map(\.id)
        )
    }

    func testRegularTabDropsAboveSplitAtThePresentedBoundary() throws {
        let profile = Profile(name: "Regular Tab Boundary")
        let browser = makeSafariExtensionTestBrowserManager(profile: profile)
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profile.id
            )
        )
        let tabs = (0..<4).map { index in
            browser.regularTabLifecycleOwner.createNewTab(
                url: "https://regular-tab-boundary-\(index).example",
                in: space,
                activate: false
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(tabs[1].id), .regularTab(tabs[2].id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        browser.windowRegistry.register(windowState)
        let context = WindowSidebarContext.make(
            browserManager: browser,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )
        let pasteboard = makePasteboard(
            item: SumiDragItem(tabId: tabs[3].id, title: "Trailing"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .spaceRegular(space.id),
                sourceItemId: tabs[3].id,
                sourceItemKind: .tab
            )
        )

        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: pasteboard,
            resolution: SidebarDropResolution(
                slot: .spaceRegular(spaceId: space.id, slot: 1),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        XCTAssertEqual(
            browser.regularTabCollectionOwner.tabs(in: space.id).map(\.id),
            [tabs[0].id, tabs[3].id, tabs[1].id, tabs[2].id]
        )
        XCTAssertEqual(
            SidebarVisualSceneProjection.regularRun(
                tabIDs: browser.regularTabCollectionOwner.tabs(in: space.id).map(\.id),
                groups: browser.splitGroupSidebarOrdering.regularGroups(for: space.id)
            ).rows.map(\.identity),
            [.tab(tabs[0].id), .tab(tabs[3].id), .splitGroup(group.id)]
        )
    }

    func testRegularTabDropsImmediatelyBelowSplitAtThePresentedBoundary() throws {
        let profile = Profile(name: "Regular Tab Below Split Boundary")
        let browser = makeSafariExtensionTestBrowserManager(profile: profile)
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profile.id
            )
        )
        let tabs = (0..<4).map { index in
            browser.regularTabLifecycleOwner.createNewTab(
                url: "https://regular-tab-below-split-\(index).example",
                in: space,
                activate: false
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(tabs[1].id), .regularTab(tabs[2].id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        browser.windowRegistry.register(windowState)
        let context = WindowSidebarContext.make(
            browserManager: browser,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )
        let pasteboard = makePasteboard(
            item: SumiDragItem(tabId: tabs[0].id, title: "Leading"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .spaceRegular(space.id),
                sourceItemId: tabs[0].id,
                sourceItemKind: .tab
            )
        )
        let run = SidebarVisualSceneProjection.regularRun(
            tabIDs: tabs.map(\.id),
            groups: [group]
        )

        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: pasteboard,
            resolution: SidebarDropResolution(
                slot: .spaceRegular(spaceId: space.id, slot: 2),
                folderIntent: .none,
                activeHoveredFolderId: nil,
                presentedRegularBoundary: run.boundary(at: 2)
            ),
            windowState: windowState
        ))
        XCTAssertEqual(
            SidebarVisualSceneProjection.regularRun(
                tabIDs: browser.regularTabCollectionOwner.tabs(in: space.id).map(\.id),
                groups: browser.splitGroupSidebarOrdering.regularGroups(for: space.id)
            ).rows.map(\.identity),
            [.splitGroup(group.id), .tab(tabs[0].id), .tab(tabs[3].id)]
        )
    }

    func makePasteboard(
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

    func unusedURLDropService() -> SidebarURLDropService {
        URLDropHarness().service
    }

    func makeFavoritePin(
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
                    role: .favorite,
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
final class RecordingDragOperations: SidebarDragOperationExecuting {
    var payload: DragOperation.Payload?
    private(set) var resolvedItems: [SumiDragItem] = []
    private(set) var performed: [SidebarDragCommitIntent] = []

    init(payload: DragOperation.Payload?) {
        self.payload = payload
    }

    func resolveSidebarDragPayload(for item: SumiDragItem) -> DragOperation.Payload? {
        resolvedItems.append(item)
        return payload
    }

    func performSidebarDragCommit(_ intent: SidebarDragCommitIntent) -> Bool {
        performed.append(intent)
        return true
    }
}

@MainActor
final class RecordingSplitPairing: SidebarSplitPairingCommitting {
    private(set) var targets: [SidebarSplitPairingTarget] = []

    func commit(
        _ payload: DragOperation.Payload,
        to target: SidebarSplitPairingTarget,
        in windowState: BrowserWindowState
    ) -> Bool {
        targets.append(target)
        return true
    }
}

@MainActor
final class URLDropHarness {
    let tabOpening = URLDropTabOpening()
    let nativeSurfaces = URLDropNativeSurfaces()
    let destinations: URLDropDestinations
    let shortcutInsertion = URLDropShortcutInsertion()
    let service: SidebarURLDropService

    init(spaces: [UUID: Space] = [:]) {
        let destinations = URLDropDestinations(spaces: spaces)
        self.destinations = destinations
        self.service = SidebarURLDropService(
            pageOpening: SidebarURLDropTabOpening(
                tabOpening: tabOpening,
                nativeSurfaces: nativeSurfaces
            ),
            destinations: destinations,
            shortcutInsertion: shortcutInsertion
        )
    }
}

@MainActor
final class URLDropTabOpening: URLTabOpening {
    struct Request { let url: String; let context: BrowserTabOpenContext }
    var requests: [Request] = []

    func openNewTab(url: String, context: BrowserTabOpenContext) -> Tab {
        requests.append(Request(url: url, context: context))
        return Tab(url: URL(string: url)!, loadsCachedFaviconOnInit: false)
    }
}

@MainActor
final class URLDropNativeSurfaces: NativeBrowserSurfaceOpening {
    func openNativeBrowserSurface(
        _ kind: SumiNativeBrowserSurfaceKind,
        url: URL,
        in windowState: BrowserWindowState,
        preferredSpaceId: UUID?
    ) {}
}

@MainActor
final class URLDropDestinations: SidebarURLDropDestinationResolving {
    let spaces: [UUID: Space]

    init(spaces: [UUID: Space]) {
        self.spaces = spaces
    }

    func space(_ spaceID: UUID) -> Space? { spaces[spaceID] }
    func folder(_ folderID: UUID) -> (folder: TabFolder, space: Space)? { nil }
    func favoriteInsertion(
        in windowState: BrowserWindowState,
        at index: Int
    ) -> FavoriteShortcutPlacementOwner.InsertionPlan? { nil }
}

@MainActor
final class URLDropShortcutInsertion: ShortcutURLInserting {
    func insert(
        _ url: URL,
        placement: ShortcutURLPlacement,
        in windowState: BrowserWindowState
    ) -> Bool {
        false
    }
}
