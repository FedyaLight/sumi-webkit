import Combine
import Foundation
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SidebarConsumerBoundariesTests: XCTestCase {
    func testInventorySnapshotPreservesCanonicalNestedOrdering() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = Space(name: "Work")
        let root = TabFolder(name: "Root", spaceId: space.id, index: 0)
        let child = TabFolder(
            name: "Child",
            spaceId: space.id,
            parentFolderId: root.id,
            index: 0
        )
        let nestedPin = makePin(
            title: "Nested",
            spaceID: space.id,
            folderID: root.id,
            index: 1
        )
        let topPin = makePin(
            title: "Top",
            spaceID: space.id,
            folderID: nil,
            index: 1
        )
        let regular = Tab(
            url: URL(string: "https://regular.example")!,
            spaceId: space.id,
            index: 0,
            loadsCachedFaviconOnInit: false
        )
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            space.id: [regular],
        ])
        tabManager.folderCollectionStateOwner.replaceFoldersBySpace([
            space.id: [child, root],
        ])
        tabManager.shortcutPinCollectionStateOwner.replaceSpacePinnedShortcuts([
            space.id: [topPin, nestedPin],
        ])

        let snapshot = try XCTUnwrap(
            SidebarConsumerTestSupport.roles(tabManager: tabManager)
                .inventory.snapshot(for: space.id)
        )

        XCTAssertEqual(snapshot.regularTabs.map(\.id), [regular.id])
        XCTAssertEqual(snapshot.topLevelItems, [.folder(root.id), .shortcut(topPin.id)])
        XCTAssertEqual(
            snapshot.folderItems(for: root.id),
            [.folder(child.id), .shortcut(nestedPin.id)]
        )
        XCTAssertEqual(snapshot.recursiveChildCount(for: root.id), 2)
    }

    func testWindowSelectionRejectsReplacedWindowObjectWithSameIdentity() throws {
        let tabManager = try makeInMemoryTabManager()
        let registry = WindowRegistry()
        let windowID = UUID()
        let original = BrowserWindowState(id: windowID)
        let replacement = BrowserWindowState(id: windowID)
        registry.register(original)
        let identity = SidebarWindowIdentityQuery(registry: { registry })
        let splitQuery = WindowSplitQuery(
            tabManager: { tabManager },
            windowState: { registry.windows[$0] },
            previewIsActive: { _ in false }
        )
        let selection = SidebarWindowSelectionQuery(
            runtimeIsAlive: { true },
            windows: identity,
            windowTabs: BrowserWindowTabContext(
                selectionService: { nil },
                tabStore: { nil },
                windows: { Array(registry.windows.values) },
                liveShortcutTabs: { _ in [] },
                visibleSplitTabIds: { _ in [] }
            ),
            shortcutPresentation: tabManager.shortcutPresentationOwner,
            splitQuery: splitQuery
        )

        XCTAssertTrue(selection.isCurrent(original))
        registry.unregister(windowID)
        registry.register(replacement)

        XCTAssertFalse(selection.isCurrent(original))
        XCTAssertNil(selection.currentTab(in: original))
        XCTAssertTrue(selection.isCurrent(replacement))
    }

    func testPinFolderCommandsResolveDestinationAtCommitAndFailClosed() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = Space(name: "Work")
        let folder = TabFolder(name: "Folder", spaceId: space.id, index: 0)
        let existing = makePin(
            title: "Existing",
            spaceID: space.id,
            folderID: folder.id,
            index: 0
        )
        let moving = makePin(
            title: "Moving",
            spaceID: space.id,
            folderID: nil,
            index: 0
        )
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.folderCollectionStateOwner.replaceFoldersBySpace([
            space.id: [folder],
        ])
        tabManager.shortcutPinCollectionStateOwner.replaceSpacePinnedShortcuts([
            space.id: [moving, existing],
        ])
        let runtime = SidebarRuntimeAvailabilityOracle()
        let roles = SidebarConsumerTestSupport.roles(
            tabManager: tabManager,
            runtimeIsAlive: { runtime.isAlive }
        )

        XCTAssertTrue(roles.pinCommands.move(moving, toFolder: folder.id))
        let moved = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: moving.id)
        )
        XCTAssertEqual(moved.folderId, folder.id)
        XCTAssertEqual(moved.index, 1)

        runtime.isAlive = false
        XCTAssertFalse(roles.pinCommands.remove(moved))
        XCTAssertNotNil(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: moved.id)
        )
    }

    func testSpaceLifecycleUsesAuthoritativeCatalogAndFailsClosed() throws {
        let tabManager = try makeInMemoryTabManager()
        let first = Space(name: "First")
        let second = Space(name: "Second")
        tabManager.spaceStateOwner.replaceSpaces([first, second])
        tabManager.spaceStateOwner.replaceCurrentSpace(first)
        let runtime = SidebarRuntimeAvailabilityOracle()
        let lifecycle = SidebarConsumerTestSupport.roles(
            tabManager: tabManager,
            runtimeIsAlive: { runtime.isAlive }
        ).lifecycle
        var catalogChanges = 0
        let catalogCancellable = tabManager.tabStructureEventBus
            .scopedStructureChangesPublisher
            .filter(\.affectsSpaceCatalog)
            .sink { _ in catalogChanges += 1 }

        try lifecycle.renameSpace(first.id, to: "Renamed")
        XCTAssertEqual(tabManager.spaceStateOwner.space(with: first.id)?.name, "Renamed")
        XCTAssertTrue(lifecycle.reorderSpace(second.id, to: 0))
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [second.id, first.id])
        XCTAssertEqual(catalogChanges, 2)

        runtime.isAlive = false
        XCTAssertNil(lifecycle.createSpace(name: "Rejected", icon: "", profileID: nil))
        XCTAssertFalse(lifecycle.reorderSpace(first.id, to: 0))
        XCTAssertThrowsError(try lifecycle.renameSpace(first.id, to: "Rejected"))
        XCTAssertTrue(lifecycle.availableSpaces(isIncognito: false, ephemeralSpaces: []).isEmpty)
        withExtendedLifetime(catalogCancellable) {}
    }

    func testScopedSnapshotModelCatchesUpBeforeResubscribingAfterHiddenMutation() throws {
        let snapshots = PassthroughSubject<Int, Never>()
        let probe = SidebarSubscriptionProbe()
        var currentSnapshot = 0

        XCTAssertEqual(probe.subscriptions, 0)
        var model: SidebarScopedSnapshotModel<Int>? = SidebarScopedSnapshotModel(
            current: { currentSnapshot },
            changes: tracked(
                snapshots.eraseToAnyPublisher(),
                probe: probe
            )
        )
        XCTAssertEqual(probe.subscriptions, 0)
        model?.setActive(true)
        XCTAssertEqual(probe.subscriptions, 1)

        let snapshotExpectation = expectation(description: "snapshot delivered")
        var observationCancellables = Set<AnyCancellable>()
        model?.$snapshot
            .dropFirst()
            .filter { $0 == 7 }
            .prefix(1)
            .sink { _ in snapshotExpectation.fulfill() }
            .store(in: &observationCancellables)

        currentSnapshot = 7
        snapshots.send(currentSnapshot)
        wait(for: [snapshotExpectation], timeout: 1)
        XCTAssertEqual(model?.snapshot, 7)
        observationCancellables.removeAll()

        model?.setActive(false)
        XCTAssertEqual(probe.cancellations, 1)
        currentSnapshot = 8
        snapshots.send(currentSnapshot)
        XCTAssertEqual(model?.snapshot, 7)

        model?.setActive(true)
        XCTAssertEqual(model?.snapshot, 8)
        XCTAssertEqual(probe.subscriptions, 2)

        let releasedModel = WeakTestReference(model)
        model = nil
        XCTAssertNil(releasedModel.value)
        XCTAssertEqual(probe.cancellations, 2)
    }

    func testMountedIncognitoInventoryPublishesExactAddCloseAndCatalogChanges() {
        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        let tab = Tab(
            url: URL(string: "https://private.example")!,
            loadsCachedFaviconOnInit: false
        )
        let space = Space(name: "Private")
        var tabSnapshots: [[UUID]] = []
        var spaceSnapshots: [[UUID]] = []
        let tabCancellable = windowState.ephemeralInventoryAuthority
            .tabInventoryChanges
            .sink {
                tabSnapshots.append(windowState.ephemeralTabs.map(\.id))
            }
        let spaceCancellable = windowState.ephemeralInventoryAuthority
            .spaceCatalogChanges
            .sink {
                spaceSnapshots.append(windowState.ephemeralSpaces.map(\.id))
            }

        windowState.appendEphemeralTab(tab)
        windowState.removeEphemeralTab(id: tab.id)
        windowState.replaceEphemeralSpaces([space])
        windowState.removeAllEphemeralSpaces()

        XCTAssertEqual(tabSnapshots, [[tab.id], []])
        XCTAssertEqual(spaceSnapshots, [[space.id], []])
        withExtendedLifetime((tabCancellable, spaceCancellable)) {}
    }

    func testMountedIncognitoInventoryPublishesSameIDPhysicalReplacements() {
        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        let tabID = UUID()
        let originalTab = Tab(
            id: tabID,
            url: URL(string: "https://original-private.example")!,
            loadsCachedFaviconOnInit: false
        )
        let replacementTab = Tab(
            id: tabID,
            url: URL(string: "https://replacement-private.example")!,
            loadsCachedFaviconOnInit: false
        )
        let spaceID = UUID()
        let originalSpace = Space(id: spaceID, name: "Original Private")
        let replacementSpace = Space(id: spaceID, name: "Replacement Private")
        windowState.replaceEphemeralTabs([originalTab])
        windowState.replaceEphemeralSpaces([originalSpace])
        let tabModel = SidebarScopedSnapshotModel<[Tab]>(
            current: { windowState.ephemeralTabs },
            changes: windowState.ephemeralInventoryAuthority
                .tabInventoryChanges
                .map { windowState.ephemeralTabs }
                .eraseToAnyPublisher()
        )
        let spaceModel = SidebarScopedSnapshotModel<[Space]>(
            current: { windowState.ephemeralSpaces },
            changes: windowState.ephemeralInventoryAuthority
                .spaceCatalogChanges
                .map { windowState.ephemeralSpaces }
                .eraseToAnyPublisher()
        )
        tabModel.setActive(true)
        spaceModel.setActive(true)
        let tabReplacementDelivered = expectation(
            description: "mounted tab reader receives physical replacement"
        )
        let spaceReplacementDelivered = expectation(
            description: "mounted space reader receives physical replacement"
        )
        let tabCancellable = tabModel.$snapshot
            .filter { $0.first === replacementTab }
            .prefix(1)
            .sink { _ in tabReplacementDelivered.fulfill() }
        let spaceCancellable = spaceModel.$snapshot
            .filter { $0.first === replacementSpace }
            .prefix(1)
            .sink { _ in spaceReplacementDelivered.fulfill() }

        windowState.replaceEphemeralTabs([replacementTab])
        windowState.replaceEphemeralSpaces([replacementSpace])

        wait(
            for: [tabReplacementDelivered, spaceReplacementDelivered],
            timeout: 1
        )
        XCTAssertTrue(tabModel.snapshot.first === replacementTab)
        XCTAssertTrue(spaceModel.snapshot.first === replacementSpace)
        tabModel.setActive(false)
        spaceModel.setActive(false)
        withExtendedLifetime((tabCancellable, spaceCancellable)) {}
    }

    func testStaleSameIDRegularRollbackHasNoEffectsOnReplacement() async throws {
        let windowState = BrowserWindowState()
        let space = Space(name: "Rollback")
        windowState.currentSpaceId = space.id
        let sharedID = UUID()
        let staleTab = Tab(
            id: sharedID,
            url: URL(string: "https://stale-regular.example")!,
            spaceId: space.id,
            loadsCachedFaviconOnInit: false
        )
        let replacementTab = Tab(
            id: sharedID,
            url: URL(string: "https://replacement-regular.example")!,
            spaceId: space.id,
            loadsCachedFaviconOnInit: false
        )
        windowState.currentTabId = replacementTab.id
        let tabs = try makeInMemoryTabManager()
        tabs.spaceStateOwner.replaceSpaces([space])
        tabs.regularTabCollectionStateOwner.replaceTabsBySpace([
            space.id: [replacementTab],
        ])
        tabs.runtimeStateCoalescer.enqueue(runtimeState(for: replacementTab))
        let webView = WKWebView()
        let navigationDelegate = WebViewNavigationDelegateProbe()
        webView.navigationDelegate = navigationDelegate

        WebKitChildTabRollback.discard(
            staleTab,
            webView: webView,
            residence: .regular(spaceID: space.id),
            sourceWindow: windowState,
            tabs: tabs
        )

        XCTAssertTrue(
            tabs.regularTabCollectionOwner.tabs(in: space.id).first
                === replacementTab
        )
        XCTAssertEqual(windowState.currentTabId, replacementTab.id)
        XCTAssertTrue(webView.navigationDelegate === navigationDelegate)
        let flushedRuntimeStateCount =
            await tabs.runtimeStateCoalescer.flushImmediately()
        XCTAssertEqual(flushedRuntimeStateCount, 1)
    }

    func testStaleSameIDEphemeralRollbackHasNoEffectsOnReplacement() async throws {
        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        let sharedID = UUID()
        let staleTab = Tab(
            id: sharedID,
            url: URL(string: "https://stale-private.example")!,
            loadsCachedFaviconOnInit: false
        )
        let replacementTab = Tab(
            id: sharedID,
            url: URL(string: "https://replacement-private.example")!,
            loadsCachedFaviconOnInit: false
        )
        windowState.replaceEphemeralTabs([replacementTab])
        windowState.currentTabId = replacementTab.id
        let tabs = try makeInMemoryTabManager()
        tabs.runtimeStateCoalescer.enqueue(runtimeState(for: replacementTab))
        let webView = WKWebView()
        let navigationDelegate = WebViewNavigationDelegateProbe()
        webView.navigationDelegate = navigationDelegate

        WebKitChildTabRollback.discard(
            staleTab,
            webView: webView,
            residence: .ephemeral(previousTabID: nil),
            sourceWindow: windowState,
            tabs: tabs
        )

        XCTAssertTrue(windowState.ephemeralTabs.first === replacementTab)
        XCTAssertEqual(windowState.currentTabId, replacementTab.id)
        XCTAssertTrue(webView.navigationDelegate === navigationDelegate)
        let flushedRuntimeStateCount =
            await tabs.runtimeStateCoalescer.flushImmediately()
        XCTAssertEqual(flushedRuntimeStateCount, 1)
        XCTAssertTrue(windowState.removeEphemeralTab(ifIdentical: replacementTab))
        XCTAssertTrue(windowState.ephemeralTabs.isEmpty)
    }

    func testIncognitoSnapshotReaderCatchesUpAfterHiddenMutation() {
        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        let model = SidebarScopedSnapshotModel<[UUID]>(
            current: { windowState.ephemeralTabs.map(\.id) },
            changes: windowState.ephemeralInventoryAuthority
                .tabInventoryChanges
                .map { windowState.ephemeralTabs.map(\.id) }
                .eraseToAnyPublisher()
        )
        model.setActive(true)
        model.setActive(false)
        let hiddenTab = Tab(
            url: URL(string: "https://hidden-private.example")!,
            loadsCachedFaviconOnInit: false
        )

        windowState.appendEphemeralTab(hiddenTab)
        XCTAssertEqual(model.snapshot, [])

        model.setActive(true)
        XCTAssertEqual(model.snapshot, [hiddenTab.id])
    }

    func testScopedSnapshotModelCatchesMutationReenteringDemandRead() {
        let changes = PassthroughSubject<Int, Never>()
        var currentSnapshot = 0
        var shouldMutateDuringRead = false
        let model = SidebarScopedSnapshotModel<Int>(
            current: {
                let valueAtReadStart = currentSnapshot
                if shouldMutateDuringRead {
                    shouldMutateDuringRead = false
                    currentSnapshot = 1
                    changes.send(1)
                }
                return valueAtReadStart
            },
            changes: changes.eraseToAnyPublisher()
        )
        let delivered = expectation(description: "reentrant mutation delivered")
        let cancellable = model.$snapshot
            .filter { $0 == 1 }
            .prefix(1)
            .sink { _ in delivered.fulfill() }

        shouldMutateDuringRead = true
        model.setActive(true)

        wait(for: [delivered], timeout: 1)
        XCTAssertEqual(model.snapshot, 1)
        withExtendedLifetime(cancellable) {}
    }

    func testScopedSnapshotModelRejectsQueuedDeliveryAfterCancellation() {
        let changes = PassthroughSubject<Int, Never>()
        let model = SidebarScopedSnapshotModel<Int>(
            current: { 0 },
            changes: changes.eraseToAnyPublisher()
        )
        model.setActive(true)

        changes.send(7)
        model.setActive(false)
        let mainRunLoopDrained = expectation(description: "main run loop drained")
        DispatchQueue.main.async {
            mainRunLoopDrained.fulfill()
        }

        wait(for: [mainRunLoopDrained], timeout: 1)
        XCTAssertEqual(model.snapshot, 0)
    }

    func testPageInventoryChangesIgnoreUnrelatedSpaceBeforeRecomputation() {
        let bus = TabStructureEventBus()
        let targetSpaceID = UUID()
        let unrelatedSpaceID = UUID()
        let targetWindowID = UUID()
        let updates = SidebarInventoryUpdates(
            changes: bus.scopedStructureChangesPublisher
        )
        var recomputations = 0
        var catalogRecomputations = 0
        let cancellable = updates.pageChanges(
            windowID: targetWindowID,
            spaceID: targetSpaceID,
            profileID: nil
        )
        .sink { _ in recomputations += 1 }
        let catalogCancellable = updates.catalogChanges.sink { _ in
            catalogRecomputations += 1
        }

        bus.publishStructureChanged(scope: .space(unrelatedSpaceID))
        XCTAssertEqual(recomputations, 0)
        XCTAssertEqual(catalogRecomputations, 0)

        bus.publishStructureChanged(scope: .space(targetSpaceID))
        XCTAssertEqual(recomputations, 1)
        XCTAssertEqual(catalogRecomputations, 0)

        bus.publishStructureChanged(scope: .space(targetSpaceID, catalog: true))
        XCTAssertEqual(recomputations, 2)
        XCTAssertEqual(catalogRecomputations, 1)
        withExtendedLifetime((cancellable, catalogCancellable)) {}
    }

    private func makePin(
        title: String,
        spaceID: UUID,
        folderID: UUID?,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceID,
            index: index,
            folderId: folderID,
            launchURL: URL(string: "https://\(title.lowercased()).example")!,
            title: title
        )
    }

    private func tracked<Output>(
        _ publisher: AnyPublisher<Output, Never>,
        probe: SidebarSubscriptionProbe
    ) -> AnyPublisher<Output, Never> {
        publisher
            .handleEvents(
                receiveSubscription: { _ in probe.subscriptions += 1 },
                receiveCancel: { probe.cancellations += 1 }
            )
            .eraseToAnyPublisher()
    }

    private func runtimeState(for tab: Tab) -> TabRuntimeStateUpdate {
        TabRuntimeStateUpdate(
            id: tab.id,
            urlString: tab.url.absoluteString,
            currentURLString: tab.url.absoluteString,
            name: tab.name,
            canGoBack: false,
            canGoForward: false
        )
    }
}

@MainActor
private final class SidebarRuntimeAvailabilityOracle {
    var isAlive = true
}

@MainActor
private final class SidebarSubscriptionProbe {
    var subscriptions = 0
    var cancellations = 0
}

private final class WebViewNavigationDelegateProbe: NSObject,
    WKNavigationDelegate {}
