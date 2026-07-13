import Combine
import Foundation
@testable import Sumi
import XCTest

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
        var runtimeIsAlive = true
        let roles = SidebarConsumerTestSupport.roles(
            tabManager: tabManager,
            runtimeIsAlive: { runtimeIsAlive }
        )

        XCTAssertTrue(roles.pinCommands.move(moving, toFolder: folder.id))
        let moved = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: moving.id)
        )
        XCTAssertEqual(moved.folderId, folder.id)
        XCTAssertEqual(moved.index, 1)

        runtimeIsAlive = false
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
        var runtimeIsAlive = true
        let lifecycle = SidebarConsumerTestSupport.roles(
            tabManager: tabManager,
            runtimeIsAlive: { runtimeIsAlive }
        ).lifecycle

        try lifecycle.renameSpace(first.id, to: "Renamed")
        XCTAssertEqual(tabManager.spaceStateOwner.space(with: first.id)?.name, "Renamed")
        XCTAssertTrue(lifecycle.reorderSpace(second.id, to: 0))
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [second.id, first.id])

        runtimeIsAlive = false
        XCTAssertNil(lifecycle.createSpace(name: "Rejected", icon: "", profileID: nil))
        XCTAssertFalse(lifecycle.reorderSpace(first.id, to: 0))
        XCTAssertThrowsError(try lifecycle.renameSpace(first.id, to: "Rejected"))
        XCTAssertTrue(lifecycle.availableSpaces(isIncognito: false, ephemeralSpaces: []).isEmpty)
    }

    func testPageModelSubscribesOnlyForItsLifetimeAndScopesRevisions() throws {
        let browserManager = BrowserManager()
        let roles = SidebarConsumerTestSupport.roles(
            tabManager: browserManager.tabManager
        )
        let browserContext = SidebarBrowserContext.live(
            browserManager: browserManager,
            spaceLifecycle: roles.lifecycle
        )
        let inventory = PassthroughSubject<UInt, Never>()
        let profiles = PassthroughSubject<[Profile], Never>()
        let liveFolders = PassthroughSubject<Void, Never>()
        let profileRuntime = PassthroughSubject<Void, Never>()
        let probe = SidebarSubscriptionProbe()
        let streams = SidebarUpdateStreams(
            inventoryRevision: tracked(
                inventory.eraseToAnyPublisher(),
                probe: probe
            ),
            profiles: tracked(
                profiles.eraseToAnyPublisher(),
                probe: probe
            ),
            profileRuntimeChanged: tracked(
                profileRuntime.eraseToAnyPublisher(),
                probe: probe
            ),
            liveFoldersChanged: tracked(
                liveFolders.eraseToAnyPublisher(),
                probe: probe
            )
        )

        XCTAssertEqual(probe.subscriptions, 0)
        var model: SidebarSpacePageModel? = SidebarSpacePageModel(
            browserContext: browserContext,
            spaceLifecycle: roles.lifecycle,
            updateStreams: streams
        )
        XCTAssertEqual(probe.subscriptions, 0)
        model?.setActive(true)
        XCTAssertEqual(probe.subscriptions, 4)

        let inventoryExpectation = expectation(
            description: "inventory revision delivered"
        )
        let liveFolderExpectation = expectation(
            description: "live-folder revision delivered"
        )
        var observationCancellables = Set<AnyCancellable>()
        model?.$structuralRevision
            .dropFirst()
            .filter { $0 == 7 }
            .prefix(1)
            .sink { _ in inventoryExpectation.fulfill() }
            .store(in: &observationCancellables)
        model?.$liveFolderRevision
            .dropFirst()
            .filter { $0 == 1 }
            .prefix(1)
            .sink { _ in liveFolderExpectation.fulfill() }
            .store(in: &observationCancellables)

        inventory.send(7)
        liveFolders.send(())
        wait(
            for: [inventoryExpectation, liveFolderExpectation],
            timeout: 1
        )
        XCTAssertEqual(model?.structuralRevision, 7)
        XCTAssertEqual(model?.liveFolderRevision, 1)
        observationCancellables.removeAll()

        model?.setActive(false)
        XCTAssertEqual(probe.cancellations, 4)
        inventory.send(8)
        XCTAssertEqual(model?.structuralRevision, 7)

        weak var releasedModel = model
        model = nil
        XCTAssertNil(releasedModel)
        XCTAssertEqual(probe.cancellations, 4)
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
}

@MainActor
private final class SidebarSubscriptionProbe {
    var subscriptions = 0
    var cancellations = 0
}
