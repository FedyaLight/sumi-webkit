import Combine
import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class ShortcutPinAtomicityTests: XCTestCase {
    func testRemoveWithDetachedRuntimePreservesPinAndLiveRegistry() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = try XCTUnwrap(
            tabManager.shortcutPinStoreOwner.insert(
                makeSpacePin(spaceId: space.id),
                at: 0
            )
        )
        let windowId = UUID()
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )
        tabManager.detachBrowserRuntime()

        tabManager.shortcutPinCommandOwner.removeShortcutPin(pin)

        XCTAssertNotNil(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id)
        )
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: windowId),
            liveTab
        )
    }

    func testHeadlessStructuralStoreCanInsertAndMoveIntoRegularFolder() throws {
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let folder = tabManager.folderMutationOwner.createFolder(for: space.id)
        let source = try XCTUnwrap(
            tabManager.shortcutPinStoreOwner.insert(
                makeSpacePin(spaceId: space.id),
                at: 0
            )
        )
        let candidate = makeSpacePin(
            spaceId: space.id,
            folderId: folder.id
        )

        let inserted = try XCTUnwrap(
            tabManager.shortcutPinStoreOwner.insert(candidate, at: 0)
        )
        let moved = try XCTUnwrap(
            tabManager.shortcutPinStoreOwner.move(
                source,
                to: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: folder.id,
                index: 0
            )
        )

        let pins = tabManager.shortcutPinCollectionStateOwner
            .spacePinnedPins(for: space.id)
        XCTAssertEqual(Set(pins.map(\.id)), [inserted.id, moved.id])
        XCTAssertTrue(pins.allSatisfy { $0.folderId == folder.id })
    }

    func testStructuralStoreRejectsDanglingAndCrossSpaceFolderIdentity() throws {
        let tabManager = try makeInMemoryTabManager()
        let sourceSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Source"
        )
        let targetSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Target"
        )
        let sourceFolder = tabManager.folderMutationOwner.createFolder(
            for: sourceSpace.id
        )
        let source = try XCTUnwrap(
            tabManager.shortcutPinStoreOwner.insert(
                makeSpacePin(spaceId: targetSpace.id),
                at: 0
            )
        )
        let crossSpace = makeSpacePin(
            spaceId: targetSpace.id,
            folderId: sourceFolder.id
        )
        let dangling = makeSpacePin(
            spaceId: targetSpace.id,
            folderId: UUID()
        )

        XCTAssertNil(tabManager.shortcutPinStoreOwner.insert(crossSpace, at: 0))
        XCTAssertNil(tabManager.shortcutPinStoreOwner.insert(dangling, at: 0))
        XCTAssertNil(
            tabManager.shortcutPinStoreOwner.insert(
                makeSpacePin(spaceId: UUID()),
                at: 0
            )
        )
        XCTAssertNil(
            tabManager.shortcutPinCommandOwner.moveShortcutPin(
                source,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetSpace.id,
                folderId: sourceFolder.id,
                index: 0
            )
        )
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: targetSpace.id).map(\.id),
            [source.id]
        )
    }

    func testFullEssentialDestinationRejectsMoveWithoutLosingSource() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = try XCTUnwrap(
            tabManager.shortcutPinStoreOwner.insert(
                makeSpacePin(spaceId: space.id),
                at: 0
            )
        )
        let profileId = UUID()
        let essentials = try (0..<EssentialsShortcutPlacementOwner.CapacityPolicy.maxItems)
            .map { index in
                ShortcutPin(
                    id: UUID(),
                    role: .essential,
                    profileId: profileId,
                    index: index,
                    launchURL: try XCTUnwrap(
                        URL(string: "https://essential-\(index).example")
                    ),
                    title: "Essential \(index)"
                )
            }
        tabManager.structuralCollectionMutationOwner
            .setPinnedTabs(essentials, for: profileId)

        XCTAssertNil(
            tabManager.shortcutPinStoreOwner.move(
                source,
                to: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                index: 0
            )
        )
        XCTAssertNotNil(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id)
                .first { $0.id == source.id }
        )
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: profileId)
                .count,
            essentials.count
        )
    }

    func testPinLiveEssentialWithoutRegistryLeaseDoesNotCreateDetachedPin() throws {
        let profileId = UUID()
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { profileId }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            index: 0,
            launchURL: URL(string: "https://source.example")!,
            title: "Source"
        )
        tabManager.structuralCollectionMutationOwner
            .setPinnedTabs([source], for: profileId)
        let unregisteredTab = tabManager.tabFactory.makeTab(
            url: source.launchURL,
            name: source.title,
            spaceId: nil,
            index: 0
        )
        unregisteredTab.bindToShortcutPin(source)

        tabManager.shortcutPinCommandOwner.pinTabToSpace(
            unregisteredTab,
            spaceId: space.id
        )

        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id)
                .isEmpty
        )
        XCTAssertEqual(unregisteredTab.shortcutPinId, source.id)
    }

    func testPublicConversionRejectsCrossWindowSplitBeforePinInsertion() throws {
        let selected = BrowserWindowState()
        let splitOnly = BrowserWindowState()
        let states = [selected.id: selected, splitOnly.id: splitOnly]
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            visibleSplitTabIds: { windowId in
                windowId == splitOnly.id
                    ? [selected.currentTabId].compactMap(\.self)
                    : []
            }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split-conversion.example",
            in: space,
            activate: false
        )
        selected.currentSpaceId = space.id
        selected.currentTabId = tab.id
        splitOnly.currentSpaceId = space.id

        let converted = tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
            tab,
            role: .spacePinned,
            profileId: nil,
            spaceId: space.id,
            folderId: nil,
            at: 0,
            preferredWindowId: selected.id
        )

        XCTAssertNil(converted)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertFalse(tab.isShortcutLiveInstance)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
    }

    func testPublicConversionCommitsSelectedSplitAndPinAsOneStructuralEvent() throws {
        let window = BrowserWindowState()
        var visibleSplitIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            visibleSplitTabIds: { $0 == window.id ? visibleSplitIds : [] },
            primaryTrackedWindowId: { tabId in
                tabId == window.currentTabId ? window.id : nil
            }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://selected-split.example",
            in: space,
            activate: false
        )
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split-companion.example",
            in: space,
            activate: false
        )
        window.currentSpaceId = space.id
        window.currentTabId = tab.id
        let group = try XCTUnwrap(
            SplitGroup.make(
                tabIds: [tab.id, companion.id],
                layoutKind: .vertical,
                host: .regular(spaceId: space.id)
            )
        )
        visibleSplitIds = group.tabIds
        tabManager.splitGroupStructureOwner.upsertSplitGroup(
            group,
            schedulePersistence: false
        )
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0

        let converted = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0,
                preferredWindowId: window.id
            )
        )

        XCTAssertEqual(structuralEvents, 1)
        XCTAssertFalse(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: converted.id, in: window.id),
            tab
        )
        let convertedGroup = try XCTUnwrap(
            tabManager.splitGroupCollectionStateOwner.group(with: group.id)
        )
        XCTAssertEqual(convertedGroup.layoutTree, group.layoutTree)
        XCTAssertEqual(
            convertedGroup.member(for: tab.id),
            SplitGroupMember(
                tabId: tab.id,
                pinId: converted.id,
                origin: .spacePinned(
                    spaceId: space.id,
                    folderId: nil,
                    index: 0
                )
            )
        )
        _ = cancellable
    }

    func testStaleSplitPlanRejectsBeforePinInsertionOrFolderOpening() throws {
        let window = BrowserWindowState()
        var visibleSplitIds: [UUID] = []
        var persistedWindowIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            visibleSplitTabIds: { $0 == window.id ? visibleSplitIds : [] },
            primaryTrackedWindowId: { tabId in
                tabId == window.currentTabId ? window.id : nil
            },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let folder = tabManager.folderMutationOwner.createFolder(for: space.id)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://stale-plan.example",
            in: space,
            activate: false
        )
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://stale-plan.example/companion",
            in: space,
            activate: false
        )
        window.tabManager = tabManager
        window.currentSpaceId = space.id
        window.currentTabId = tab.id
        let group = try XCTUnwrap(
            SplitGroup.make(
                tabIds: [tab.id, companion.id],
                layoutKind: .vertical,
                host: .regular(spaceId: space.id)
            )
        )
        visibleSplitIds = group.tabIds
        tabManager.splitGroupStructureOwner.upsertSplitGroup(
            group,
            schedulePersistence: false
        )
        let preparation = tabManager.regularTabShortcutConversion
            .prepare(
                tab,
                preferredWindowId: window.id
            )
        guard case .displayed = preparation else {
            return XCTFail("Expected a valid single-window split plan")
        }
        let changedGroup = group.settingLayoutKind(.horizontal)
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        tabManager.splitGroupStructureOwner.upsertSplitGroup(
            changedGroup,
            schedulePersistence: false
        )
        structuralEvents = 0
        let windowSession = ShortcutConversionWindowSessionState(window)

        let converted = tabManager.regularTabShortcutConversion
            .commit(
                tab,
                preparation: preparation,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: folder.id,
                    index: 0,
                    opensFolder: true
                )
            )

        XCTAssertNil(converted)
        XCTAssertFalse(folder.isOpen)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIds.isEmpty)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertFalse(tab.isShortcutLiveInstance)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        XCTAssertEqual(
            tabManager.splitGroupCollectionStateOwner.group(with: group.id),
            changedGroup
        )
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(window),
            windowSession
        )
        _ = cancellable
    }

    func testHeadlessConversionRejectsPersistedSplitWithoutMutation() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://hidden-split.example",
            in: space,
            activate: false
        )
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://hidden-companion.example",
            in: space,
            activate: false
        )
        let group = try XCTUnwrap(
            SplitGroup.make(
                tabIds: [tab.id, companion.id],
                layoutKind: .vertical,
                host: .regular(spaceId: space.id)
            )
        )
        tabManager.splitGroupStructureOwner.upsertSplitGroup(
            group,
            schedulePersistence: false
        )

        let converted = tabManager.shortcutPinCommandOwner
            .convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0
            )

        XCTAssertNil(converted)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        let preservedGroup = try XCTUnwrap(
            tabManager.splitGroupCollectionStateOwner.group(with: group.id)
        )
        XCTAssertEqual(preservedGroup.tabIds, group.tabIds)
        XCTAssertEqual(preservedGroup.members, group.members)
    }

    func testPublicConversionRepairsNonDisplayingWindowAfterCommit() throws {
        let displayed = BrowserWindowState()
        let stale = BrowserWindowState()
        let states = [displayed.id: displayed, stale.id: stale]
        var structuralEvents = 0
        var persisted: [(windowId: UUID, events: Int)] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            persistWindowSession: {
                persisted.append(($0.id, structuralEvents))
            }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://displayed.example",
            in: space,
            activate: false
        )
        let fallback = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://fallback.example",
            in: space,
            activate: false
        )
        displayed.currentSpaceId = space.id
        displayed.currentTabId = tab.id
        stale.currentSpaceId = space.id
        stale.currentTabId = UUID()
        stale.activeTabForSpace[space.id] = tab.id
        stale.selectionHistory.recordRegularTabSelection(tab.id, in: space.id)
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0

        let pin = tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
            tab,
            role: .spacePinned,
            profileId: nil,
            spaceId: space.id,
            folderId: nil,
            at: 0,
            preferredWindowId: displayed.id
        )

        XCTAssertNotNil(pin)
        XCTAssertEqual(structuralEvents, 1)
        XCTAssertEqual(stale.activeTabForSpace[space.id], fallback.id)
        XCTAssertEqual(
            stale.selectionHistory.recentRegularTabIdsBySpace[space.id]?
                .contains(tab.id),
            false
        )
        XCTAssertEqual(
            persisted.filter { $0.windowId == stale.id }.map(\.events),
            [1]
        )
        _ = cancellable
    }

    private func makeSpacePin(
        spaceId: UUID,
        folderId: UUID? = nil
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: 0,
            folderId: folderId,
            launchURL: URL(string: "https://space-pin.example")!,
            title: "Space Pin"
        )
    }
}
