import SwiftData
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

private actor SuspendedTabRestorePayloadLoader: TabRestorePayloadLoading {
    private let loader: TabRestoreLoader
    private var didCapturePayload = false
    private var captureWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var wasReleased = false

    init(container: ModelContainer) {
        loader = TabRestoreLoader(container: container)
    }

    func load(defaultProfileId: UUID?) async throws -> TabRestorePayload {
        let payload = try await loader.load(defaultProfileId: defaultProfileId)
        didCapturePayload = true
        let waiters = captureWaiters
        captureWaiters.removeAll()
        waiters.forEach { $0.resume() }

        if wasReleased == false {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        return payload
    }

    func waitUntilPayloadIsCaptured() async {
        guard didCapturePayload == false else { return }
        await withCheckedContinuation { continuation in
            captureWaiters.append(continuation)
        }
    }

    func releaseCapturedPayload() {
        wasReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class DeferredPersistenceSpaceTransition {
    private(set) var stageModel: (@MainActor @Sendable () -> Bool)?
    private(set) var finishModel: (() -> Void)?
    private(set) var settlement: ProfileTransitionService.Settlement?

    func makeLifecycle() -> TabManagerWebViewLifecycleService {
        TabManagerWebViewLifecycleService(
            materializeVisibleTabWebViewIfNeeded: { _, _ in /* No-op. */ },
            loadTab: { _ in /* No-op. */ },
            unloadTab: { _ in /* No-op. */ },
            requireRemoveAllWebViews: { _, _ in /* No-op. */ },
            windowIDsTrackingWebViews: { _ in [] },
            primaryTrackedWindowId: { _ in nil },
            rebuildLiveWebViews: { _, _, _ in /* No-op. */ },
            prepareTab: { _ in /* No-op. */ },
            anyLiveWebView: { $0.resolvedCurrentWebView() },
            hasUntrackedOwnedWebView: { _ in false },
            executeSpaceProfileTransition: { [weak self] _, _, _, _, stage, finish, _, settlement in
                self?.stageModel = stage
                self?.finishModel = finish
                self?.settlement = settlement
                return .deferred
            }
        )
    }
}

@MainActor
final class TabManagerStructuralPersistenceTests: XCTestCase {
    func testStartupRestoreRequestedAtConstructionCannotOverwritePreReadinessMutation() async throws {
        let container = try makeInMemoryContainer()
        let persistedFixture = try insertCurrentFormatRestoreFixture(in: container)
        let webViewSessions = WebViewSessionRepository()
        let tabManager = TabManager(
            context: ModelContext(container),
            webViewSessions: webViewSessions,
            loadPersistedState: true,
            automaticallyStartPersistedStateLoad: false
        )
        tabManager.runtimePortsAttachmentOwner.attach(TestRuntimePorts.inactive)

        let liveSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Created Before Shell Readiness",
            profileId: persistedFixture.profileId
        )
        let liveTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/pre-readiness",
            in: liveSpace,
            activate: true
        )

        tabManager.startupRestoreLifecycle.startIfNeeded(
            runtimeIsAttached: tabManager.runtimePorts != nil,
            restore: { [weak tabManager] revision in
                tabManager?.storeRestore.loadFromStore(
                    expectedStructuralRevision: revision
                )
            }
        )
        for _ in 0..<50
        where tabManager.startupRestoreLifecycle.hasLoadedInitialData == false {
            await Task.yield()
        }

        XCTAssertTrue(tabManager.startupRestoreLifecycle.didStartPersistedStateLoad)
        XCTAssertTrue(tabManager.startupRestoreLifecycle.hasLoadedInitialData)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [liveSpace.id])
        XCTAssertEqual(
            tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[liveSpace.id]?.map(\.id),
            [liveTab.id]
        )
        XCTAssertFalse(tabManager.spaceStateOwner.spaces.contains { $0.id == persistedFixture.spaceAId })
        XCTAssertTrue(liveTab.webViewSession.isBacked(by: webViewSessions))
    }

    func testStartupRestoreDoesNotOverwriteTabCreatedWhileSnapshotLoadIsSuspended() async throws {
        let container = try makeInMemoryContainer()
        let persistedFixture = try insertCurrentFormatRestoreFixture(in: container)
        let payloadLoader = SuspendedTabRestorePayloadLoader(container: container)
        let webViewSessions = WebViewSessionRepository()
        let tabManager = TabManager(
            context: ModelContext(container),
            webViewSessions: webViewSessions,
            loadPersistedState: false
        )
        tabManager.runtimePortsAttachmentOwner.attach(TestRuntimePorts.inactive)
        let restoreService = TabStoreRestoreService(
            payloadLoader: payloadLoader,
            structuralStore: tabManager.structuralSnapshotStore,
            tabFactory: tabManager.tabFactory,
            defaultProfileId: { [weak tabManager] in
                tabManager?.runtimePorts?.defaultProfileId
            },
            structuralRevision: { [weak tabManager] in
                tabManager?.structuralLookupCoordinator.mutationRevision ?? 0
            },
            loadLifecycle: tabManager.startupRestoreLifecycle,
            structuralInstaller: tabManager.structuralInstallOwner,
            splitGroupStructure: tabManager.splitGroupStructureOwner,
            runtimePreparation: tabManager.runtimePreparationOwner,
            lazyRestore: tabManager.lazyRestoreCoordinator,
            persistence: tabManager.structuralPersistence,
            syncWorkspaceTheme: { [weak tabManager] space in
                tabManager?.runtimePorts?.syncWorkspaceThemeAcrossWindows(
                    for: space,
                    animate: false
                )
            }
        )

        let restoreTask = Task { @MainActor in
            await restoreService.loadFromStoreAwaitingResult()
        }
        await payloadLoader.waitUntilPayloadIsCaptured()

        let liveSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Created During Restore",
            profileId: persistedFixture.profileId
        )
        let liveWebView = WKWebView()
        let liveTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/live",
            in: liveSpace,
            activate: false
        )
        liveTab.replaceUntrackedWebView(liveWebView)

        await payloadLoader.releaseCapturedPayload()
        let didInstallPersistedSnapshot = await restoreTask.value

        XCTAssertFalse(didInstallPersistedSnapshot)
        XCTAssertTrue(tabManager.startupRestoreLifecycle.hasLoadedInitialData)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [liveSpace.id])
        XCTAssertEqual(
            tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[liveSpace.id]?.map(\.id),
            [liveTab.id]
        )
        XCTAssertTrue(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id) === liveTab)
        XCTAssertTrue(liveTab.webViewSession.isBacked(by: webViewSessions))
        XCTAssertTrue(liveTab.webViewSession.untrackedWebView === liveWebView)
        XCTAssertFalse(tabManager.spaceStateOwner.spaces.contains { $0.id == persistedFixture.spaceAId })

        try await waitForStore(in: container) { context in
            try fetchTab(liveTab.id, in: context) != nil
        }
    }

    func testIncrementalAddAndRemoveRegularTabPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: UUID())
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: true)

        try await waitForStore(in: container) { context in
            guard let storedTab = try fetchTab(tab.id, in: context) else { return false }
            return storedTab.spaceId == space.id
                && storedTab.isPinned == false
                && storedTab.isSpacePinned == false
        }

        var context = ModelContext(container)
        let storedTab = try XCTUnwrap(fetchTab(tab.id, in: context))
        XCTAssertEqual(storedTab.spaceId, space.id)
        XCTAssertFalse(storedTab.isPinned)
        XCTAssertFalse(storedTab.isSpacePinned)

        tabManager.tabRemovalOwner.removeTab(tab.id)
        try await waitForStore(in: container) { context in
            try fetchTab(tab.id, in: context) == nil
        }

        context = ModelContext(container)
        XCTAssertNil(try fetchTab(tab.id, in: context))
    }

    func testCommittedInFlightFollowerReloadsAsSpaceInherited() async throws {
        let container = try makeInMemoryContainer()
        let profile = Profile(name: "Pending")
        let transition = DeferredPersistenceSpaceTransition()
        let tabManager = TabManager(
            context: container.mainContext,
            loadPersistedState: false
        )
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                currentProfileId: { profile.id },
                defaultProfileId: { profile.id },
                profile: { $0 == profile.id ? profile : nil },
                webViewLifecycle: transition.makeLifecycle()
            )
        )
        let space = Space(name: "Unassigned")
        tabManager.spaceStateOwner.replaceSpaces([space])
        let first = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://first.example",
            in: space,
            activate: false
        )
        let follower = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://follower.example",
            in: space,
            activate: false
        )

        XCTAssertNil(first.profileId)
        XCTAssertEqual(follower.profileId, profile.id)
        try await waitForStore(in: container) { context in
            try fetchTab(follower.id, in: context)?.profileId == profile.id
        }

        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.finishModel)()
        try XCTUnwrap(transition.settlement)(.committed)

        XCTAssertNil(follower.profileId)
        try await waitForStore(in: container) { context in
            guard let storedSpace = try fetchSpace(space.id, in: context),
                  let storedFollower = try fetchTab(follower.id, in: context)
            else { return false }
            return storedSpace.profileId == profile.id
                && storedFollower.profileId == nil
        }

        let restored = try await TabRestoreLoader(container: container).load(
            defaultProfileId: profile.id
        )
        let restoredFollower = try XCTUnwrap(
            restored.regularTabsBySpace[space.id]?.first {
                $0.id == follower.id
            }
        )
        XCTAssertNil(restoredFollower.profileId)
    }

    func testFullReconcileDoesNotPersistExtensionOwnedRegularTabs() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: UUID())
        let normalTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/keep",
            in: space,
            activate: false
        )
        let extensionTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "webkit-extension://extension-id/app/app.html#/page/welcome",
            in: space,
            activate: true
        )

        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, extensionTab.id)

        let didPersist = await tabManager.structuralPersistence.persistFullReconcileAwaitingResult(
            reason: "extension-owned tabs are runtime-owned"
        )

        XCTAssertTrue(didPersist)
        let context = ModelContext(container)
        XCTAssertNotNil(try fetchTab(normalTab.id, in: context))
        XCTAssertNil(try fetchTab(extensionTab.id, in: context))
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<TabsStateEntity>()).first)
        XCTAssertNil(state.currentTabID)
        XCTAssertEqual(state.currentSpaceID, space.id)
    }

    func testIncrementalPersistenceDeletesRegularTabThatBecomesExtensionOwned() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: UUID())
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/start",
            in: space,
            activate: true
        )

        try await waitForStore(in: container) { context in
            guard let storedTab = try fetchTab(tab.id, in: context),
                  let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first
            else {
                return false
            }
            return storedTab.urlString == "https://example.com/start"
                && state.currentTabID == tab.id
                && state.currentSpaceID == space.id
        }

        tab.url = try XCTUnwrap(
            URL(string: "webkit-extension://extension-id/app/app.html#/page/migration")
        )
        tab.name = "Migration"

        tabManager.structuralPersistence.scheduleRuntimeStatePersistence(for: tab)
        let flushedCount = await tabManager.structuralPersistence.flushRuntimeStatePersistenceAwaitingResult()

        XCTAssertEqual(flushedCount, 0)
        var context = ModelContext(container)
        XCTAssertEqual(try fetchTab(tab.id, in: context)?.urlString, "https://example.com/start")

        tabManager.structuralPersistence.markRegularTabsStructurallyDirty(for: space.id)
        tabManager.structuralPersistence.scheduleStructuralPersistence()

        try await waitForStore(in: container) { context in
            let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first
            return try fetchTab(tab.id, in: context) == nil
                && state?.currentTabID == nil
                && state?.currentSpaceID == space.id
        }

        context = ModelContext(container)
        XCTAssertNil(try fetchTab(tab.id, in: context))
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<TabsStateEntity>()).first)
        XCTAssertNil(state.currentTabID)
        XCTAssertEqual(state.currentSpaceID, space.id)
    }

    func testStartupRestoreRemovesPersistedExtensionOwnedRegularTabs() async throws {
        let container = try makeInMemoryContainer()
        let profileId = UUID()
        let spaceId = UUID()
        let normalTabId = UUID()
        let webKitExtensionTabId = UUID()
        let safariExtensionTabId = UUID()

        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(
                id: spaceId,
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                index: 0,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: webKitExtensionTabId,
                urlString: "webkit-extension://extension-id/app/app.html#/page/migration",
                name: "Migration",
                isPinned: false,
                index: 0,
                spaceId: spaceId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: normalTabId,
                urlString: "https://example.com/keep",
                name: "Keep",
                isPinned: false,
                index: 1,
                spaceId: spaceId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: safariExtensionTabId,
                urlString: "safari-web-extension://extension-id/app/app.html#/page/welcome",
                name: "Welcome",
                isPinned: false,
                index: 2,
                spaceId: spaceId
            )
        )
        mutationContext.insert(
            TabsStateEntity(
                currentTabID: safariExtensionTabId,
                currentSpaceID: spaceId
            )
        )
        try mutationContext.save()

        let tabManager = makeTabManager(context: ModelContext(container))
        let didLoad = await tabManager.storeRestore.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[spaceId]?.map(\.id), [normalTabId])
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, spaceId)
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, normalTabId)

        try await waitForStore(in: container) { context in
            let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first
            return try fetchTab(webKitExtensionTabId, in: context) == nil
                && fetchTab(safariExtensionTabId, in: context) == nil
                && fetchTab(normalTabId, in: context) != nil
                && state?.currentTabID == normalTabId
                && state?.currentSpaceID == spaceId
        }
    }

    func testIncrementalFolderRelationshipPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Pinned", profileId: UUID())
        let folder = tabManager.folderMutationOwner.createFolder(for: space.id, name: "Docs")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/docs", in: space, activate: true)

        tabManager.folderMutationOwner.moveTabToFolder(tab: tab, folderId: folder.id)
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).first)

        try await waitForStore(in: container) { context in
            guard let storedFolder = try fetchFolder(folder.id, in: context),
                  let storedPin = try fetchTab(pin.id, in: context)
            else {
                return false
            }
            return storedFolder.spaceId == space.id
                && storedPin.isSpacePinned
                && storedPin.folderId == folder.id
        }

        var context = ModelContext(container)
        let storedFolder = try XCTUnwrap(fetchFolder(folder.id, in: context))
        XCTAssertEqual(storedFolder.spaceId, space.id)

        var storedPin = try XCTUnwrap(fetchTab(pin.id, in: context))
        XCTAssertTrue(storedPin.isSpacePinned)
        XCTAssertEqual(storedPin.folderId, folder.id)

        tabManager.folderMutationOwner.ungroupFolder(folder.id)
        try await waitForStore(in: container) { context in
            guard let storedPin = try fetchTab(pin.id, in: context) else { return false }
            return try fetchFolder(folder.id, in: context) == nil
                && storedPin.folderId == nil
                && storedPin.isSpacePinned
        }

        context = ModelContext(container)
        XCTAssertNil(try fetchFolder(folder.id, in: context))
        storedPin = try XCTUnwrap(fetchTab(pin.id, in: context))
        XCTAssertNil(storedPin.folderId)
        XCTAssertTrue(storedPin.isSpacePinned)
    }

    func testDeleteFolderRemovesFolderChildrenPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Pinned", profileId: UUID())
        let folder = tabManager.folderMutationOwner.createFolder(for: space.id, name: "Docs")
        let nested = try XCTUnwrap(tabManager.folderMutationOwner.createFolder(for: space.id, parentFolderId: folder.id, name: "Nested"))
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/docs", in: space, activate: true)
        let nestedTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/nested", in: space, activate: false)

        tabManager.folderMutationOwner.moveTabToFolder(tab: tab, folderId: folder.id)
        tabManager.folderMutationOwner.moveTabToFolder(tab: nestedTab, folderId: nested.id)
        let pins = tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id)
        let pinIds = Set(pins.map(\.id))
        XCTAssertEqual(pins.count, 2)

        try await waitForStore(in: container) { context in
            try fetchFolder(folder.id, in: context) != nil
                && fetchFolder(nested.id, in: context) != nil
                && pins.allSatisfy { pin in
                    (try? fetchTab(pin.id, in: context)) != nil
                }
        }

        tabManager.folderMutationOwner.deleteFolder(folder.id)
        try await waitForStore(in: container) { context in
            guard try fetchFolder(folder.id, in: context) == nil,
                  try fetchFolder(nested.id, in: context) == nil else {
                return false
            }
            for pinId in pinIds {
                if try fetchTab(pinId, in: context) != nil {
                    return false
                }
            }
            return true
        }
    }

    func testFolderOpenStatePersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Pinned", profileId: UUID())
        let folder = tabManager.folderMutationOwner.createFolder(for: space.id, name: "Docs")

        tabManager.folderMutationOwner.setFolder(folder.id, open: true)
        try await waitForStore(in: container) { context in
            try fetchFolder(folder.id, in: context)?.isOpen == true
        }

        tabManager.folderMutationOwner.setFolder(folder.id, open: false)
        try await waitForStore(in: container) { context in
            try fetchFolder(folder.id, in: context)?.isOpen == false
        }
    }

    func testTopLevelFolderPositionPersistsAfterSpacePinnedShortcuts() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Pinned", profileId: UUID())
        let firstTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/first", in: space, activate: true)
        let secondTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/second", in: space, activate: false)
        let firstPin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                firstTab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0
            )
        )
        let secondPin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                secondTab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 1
            )
        )
        let folder = tabManager.folderMutationOwner.createFolder(for: space.id, name: "Bottom")

        XCTAssertEqual(
            tabManager.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: space.id).map(\.id),
            [firstPin.id, secondPin.id, folder.id]
        )

        try await waitForStore(in: container) { context in
            guard let storedFolder = try fetchFolder(folder.id, in: context),
                  let storedFirstPin = try fetchTab(firstPin.id, in: context),
                  let storedSecondPin = try fetchTab(secondPin.id, in: context)
            else {
                return false
            }
            return storedFirstPin.index == 0
                && storedSecondPin.index == 1
                && storedFolder.index == 2
        }

        let restoredManager = makeTabManager(context: ModelContext(container))
        let didLoad = await restoredManager.storeRestore.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(
            restoredManager.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: space.id).map(\.id),
            [firstPin.id, secondPin.id, folder.id]
        )
    }

    func testIncrementalSpaceMembershipAndOrderPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let profileId = UUID()
        let spaceA = tabManager.spaceServices.catalog.createSpace(name: "A", profileId: profileId)
        let tabA = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/a", in: spaceA, activate: true)
        _ = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/a2", in: spaceA, activate: false)
        let spaceB = tabManager.spaceServices.catalog.createSpace(name: "B", profileId: profileId)
        let tabB = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/b", in: spaceB, activate: true)

        tabManager.sidebarDragRoutingOwner.moveTab(tabA.id, to: spaceB.id)
        tabManager.regularTabCollectionOwner.reorderRegularTabs(tabA, in: spaceB.id, to: 0)

        try await waitForStore(in: container) { context in
            guard let storedMovedTab = try fetchTab(tabA.id, in: context),
                  let storedExistingTab = try fetchTab(tabB.id, in: context)
            else {
                return false
            }
            return storedMovedTab.spaceId == spaceB.id
                && storedMovedTab.index == 0
                && storedExistingTab.spaceId == spaceB.id
                && storedExistingTab.index == 1
        }

        let context = ModelContext(container)
        let storedMovedTab = try XCTUnwrap(fetchTab(tabA.id, in: context))
        let storedExistingTab = try XCTUnwrap(fetchTab(tabB.id, in: context))
        XCTAssertEqual(storedMovedTab.spaceId, spaceB.id)
        XCTAssertEqual(storedMovedTab.index, 0)
        XCTAssertEqual(storedExistingTab.spaceId, spaceB.id)
        XCTAssertEqual(storedExistingTab.index, 1)
    }

    func testReorderSpaceUpdatesPersistedIndicesAndPreservesCurrentSpace() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let profileId = UUID()
        let first = tabManager.spaceServices.catalog.createSpace(name: "First", profileId: profileId)
        let second = tabManager.spaceServices.catalog.createSpace(name: "Second", profileId: profileId)
        let third = tabManager.spaceServices.catalog.createSpace(name: "Third", profileId: profileId)
        tabManager.spaceServices.activation.setActiveSpace(second)

        XCTAssertTrue(tabManager.spaceServices.catalog.reorderSpace(spaceId: first.id, to: 2))
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, second.id)

        try await waitForStore(in: container) { context in
            let storedSpaces = try fetchSpacesSortedByIndex(in: context)
            return storedSpaces.map(\.id) == [second.id, third.id, first.id]
                && storedSpaces.map(\.index) == [0, 1, 2]
        }

        let storedSpaces = try fetchSpacesSortedByIndex(in: ModelContext(container))
        XCTAssertEqual(storedSpaces.map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(storedSpaces.map(\.index), [0, 1, 2])
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, second.id)
    }

    func testReorderSpacePersistsThroughRestore() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let profileId = UUID()
        let first = tabManager.spaceServices.catalog.createSpace(name: "First", profileId: profileId)
        let second = tabManager.spaceServices.catalog.createSpace(name: "Second", profileId: profileId)
        let third = tabManager.spaceServices.catalog.createSpace(name: "Third", profileId: profileId)
        tabManager.spaceServices.activation.setActiveSpace(second)

        XCTAssertTrue(tabManager.spaceServices.catalog.reorderSpace(spaceId: first.id, to: 2))

        try await waitForStore(in: container) { context in
            try fetchSpacesSortedByIndex(in: context).map(\.id) == [second.id, third.id, first.id]
        }

        let restoredManager = makeTabManager(context: ModelContext(container))
        let didLoad = await restoredManager.storeRestore.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(restoredManager.spaceStateOwner.spaces.map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(restoredManager.spaceStateOwner.currentSpace?.id, second.id)
        XCTAssertTrue(restoredManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(restoredManager.structuralPersistence.scheduledPersistTask)
    }

    func testReorderSpaceClampsInvalidTargetIndices() throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let profileId = UUID()
        let first = tabManager.spaceServices.catalog.createSpace(name: "First", profileId: profileId)
        let second = tabManager.spaceServices.catalog.createSpace(name: "Second", profileId: profileId)
        let third = tabManager.spaceServices.catalog.createSpace(name: "Third", profileId: profileId)

        XCTAssertTrue(tabManager.spaceServices.catalog.reorderSpace(spaceId: third.id, to: -100))
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [third.id, first.id, second.id])
        XCTAssertTrue(tabManager.spaceServices.catalog.reorderSpace(spaceId: third.id, to: 100))
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [first.id, second.id, third.id])
        XCTAssertFalse(tabManager.spaceServices.catalog.reorderSpace(spaceId: UUID(), to: 0))
    }

    func testSelectionOnlyPersistenceCreatesAndUpdatesState() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Select", profileId: UUID())
        _ = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space, activate: true)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)

        try await waitForPersistedState(in: container) { state in
            state.currentSpaceID == space.id
        }
        tabManager.activeSelectionOwner.setActiveTab(second)

        try await waitForPersistedState(in: container) { state in
            state.currentTabID == second.id && state.currentSpaceID == space.id
        }
    }

    func testActiveTabStatePathsPersistSelectionWithoutSchedulingStructuralPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let profileId = UUID()
        let firstSpace = tabManager.spaceServices.catalog.createSpace(name: "First", profileId: profileId)
        let secondSpace = tabManager.spaceServices.catalog.createSpace(name: "Second", profileId: profileId)
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/first", in: firstSpace, activate: false)
        let alternate = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/alternate", in: firstSpace, activate: false)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/second", in: secondSpace, activate: false)

        tabManager.activeSelectionOwner.setActiveTab(first)
        try await waitForStore(in: container) { context in
            guard let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first else {
                return false
            }
            return try fetchTab(first.id, in: context) != nil
                && fetchTab(alternate.id, in: context) != nil
                && fetchTab(second.id, in: context) != nil
                && state.currentTabID == first.id
                && state.currentSpaceID == firstSpace.id
                && tabManager.structuralPersistence.dirtySet.isEmpty
                && tabManager.structuralPersistence.scheduledPersistTask == nil
        }

        tabManager.activeSelectionOwner.setActiveTab(second)

        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, second.id)
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, secondSpace.id)
        XCTAssertEqual(secondSpace.activeTabId, second.id)
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)
        try await waitForPersistedState(in: container) { state in
            state.currentTabID == second.id && state.currentSpaceID == secondSpace.id
        }

        tabManager.activeSelectionOwner.updateActiveTabState(alternate)

        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, alternate.id)
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, firstSpace.id)
        XCTAssertEqual(firstSpace.activeTabId, alternate.id)
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)
        try await waitForPersistedState(in: container) { state in
            state.currentTabID == alternate.id && state.currentSpaceID == firstSpace.id
        }
    }

    func testRuntimeStateBatchFlushUpdatesStoredTabFields() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Runtime", profileId: UUID())
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/initial", in: space, activate: true)

        try await waitForStore(in: container) { context in
            try fetchTab(tab.id, in: context) != nil
        }

        tab.url = try XCTUnwrap(URL(string: "https://example.com/runtime"))
        tab.name = "Runtime Updated"
        tab.canGoBack = true
        tab.canGoForward = true

        tabManager.structuralPersistence.scheduleRuntimeStatePersistence(for: tab)
        let flushedCount = await tabManager.structuralPersistence.flushRuntimeStatePersistenceAwaitingResult()

        XCTAssertEqual(flushedCount, 1)
        let context = ModelContext(container)
        let storedTab = try XCTUnwrap(fetchTab(tab.id, in: context))
        XCTAssertEqual(storedTab.urlString, "https://example.com/runtime")
        XCTAssertEqual(storedTab.currentURLString, "https://example.com/runtime")
        XCTAssertEqual(storedTab.name, "Runtime Updated")
        XCTAssertTrue(storedTab.canGoBack)
        XCTAssertTrue(storedTab.canGoForward)
    }

    func testSplitGroupLayoutPersistsThroughStoreReload() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Split", profileId: UUID())
        let tabs = [
            tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space, activate: true),
            tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false),
            tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/three", in: space, activate: false),
        ]
        let baseGroup = try XCTUnwrap(
            SplitGroup.make(
                tabIds: tabs.map(\.id),
                layoutKind: .vertical,
                activeTabId: tabs[1].id
            )
        )
        let resizedGroup = SplitGroup(
            id: baseGroup.id,
            layoutKind: .vertical,
            layoutTree: SplitLayoutSizing.updatingChildSizes(
                in: baseGroup.layoutTree,
                at: [],
                sizes: [0.2, 0.3, 0.5]
            ),
            activeTabId: tabs[1].id
        )

        tabManager.splitGroupStructureOwner.upsertSplitGroup(resizedGroup)

        try await waitForPersistedState(in: container) { state in
            guard let data = state.splitGroupsData,
                  let decoded = try? JSONDecoder().decode([SplitGroup].self, from: data),
                  let storedGroup = decoded.first(where: { $0.id == resizedGroup.id })
            else {
                return false
            }
            return storedGroup.layoutKind == resizedGroup.layoutKind
                && storedGroup.layoutTree == resizedGroup.layoutTree
                && storedGroup.activeTabId == resizedGroup.activeTabId
        }

        let restoredManager = makeTabManager(context: ModelContext(container))
        let didLoad = await restoredManager.storeRestore.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        let restoredGroup = try XCTUnwrap(restoredManager.splitGroupCollectionStateOwner.group(with: resizedGroup.id))
        XCTAssertEqual(restoredGroup.layoutKind, resizedGroup.layoutKind)
        XCTAssertEqual(restoredGroup.layoutTree, resizedGroup.layoutTree)
        XCTAssertEqual(restoredGroup.activeTabId, resizedGroup.activeTabId)
    }

    func testShortcutBackedSplitGroupPersistsThroughStoreReload() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Split", profileId: UUID())
        let regular = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/regular", in: space, activate: true)
        let pinnedSource = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/pinned",
            in: space,
            activate: false
        )
        let pin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                pinnedSource,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0
            )
        )
        let windowId = UUID()
        let livePinnedTab = tabManager.shortcutTabMaterializer.materialize(pin, in: windowId, currentSpaceId: space.id)
        let group = try XCTUnwrap(
            SplitGroup.make(
                tabIds: [regular.id, livePinnedTab.id],
                layoutKind: .vertical,
                activeTabId: livePinnedTab.id,
                host: .regular(spaceId: space.id),
                members: [
                    SplitGroupMember(
                        tabId: regular.id,
                        pinId: nil,
                        origin: .regular(spaceId: space.id, index: regular.index)
                    ),
                    SplitGroupMember(
                        tabId: livePinnedTab.id,
                        pinId: pin.id,
                        origin: .spacePinned(spaceId: space.id, folderId: nil, index: pin.index)
                    ),
                ]
            )
        )
        tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        try await waitForPersistedState(in: container) { state in
            guard let data = state.splitGroupsData,
                  let decoded = try? JSONDecoder().decode([SplitGroup].self, from: data)
            else {
                return false
            }
            return decoded.contains { $0.id == group.id && $0.contains(livePinnedTab.id) }
        }

        let restoredManager = makeTabManager(context: ModelContext(container))
        let didLoad = await restoredManager.storeRestore.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        let restoredGroup = try XCTUnwrap(restoredManager.splitGroupStructureOwner.splitGroup(containingPinId: pin.id))
        XCTAssertEqual(restoredGroup.id, group.id)
        XCTAssertTrue(restoredGroup.contains(regular.id))
        XCTAssertTrue(restoredGroup.containsPin(pin.id))
        XCTAssertFalse(restoredGroup.contains(livePinnedTab.id))
    }

    func testFullReconcileDeletesStaleEntitiesAndPreservesFolders() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Clean", profileId: UUID())
        let folder = tabManager.folderMutationOwner.createFolder(for: space.id, name: "Keep")
        _ = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/keep", in: space, activate: true)
        try await waitForStore(in: container) { context in
            try fetchFolder(folder.id, in: context) != nil
        }

        let staleSpaceId = UUID()
        let staleTabId = UUID()
        let staleFolderId = UUID()
        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(id: staleSpaceId, name: "Stale", icon: "xmark", index: 99)
        )
        mutationContext.insert(
            TabEntity(
                id: staleTabId,
                urlString: "https://example.com/stale",
                name: "Stale",
                isPinned: false,
                index: 0,
                spaceId: staleSpaceId
            )
        )
        mutationContext.insert(
            FolderEntity(
                id: staleFolderId,
                name: "Stale",
                icon: "folder",
                color: "#000000",
                spaceId: staleSpaceId,
                isOpen: false,
                index: 0
            )
        )
        try mutationContext.save()

        let didFullReconcile = await tabManager.structuralPersistence.persistFullReconcileAwaitingResult(reason: "test full reconcile")
        XCTAssertTrue(didFullReconcile)

        let context = ModelContext(container)
        XCTAssertNil(try fetchSpace(staleSpaceId, in: context))
        XCTAssertNil(try fetchTab(staleTabId, in: context))
        XCTAssertNil(try fetchFolder(staleFolderId, in: context))
        XCTAssertNotNil(try fetchFolder(folder.id, in: context))
    }

    func testStartupRestorePreservesOrderingSelectionAndDoesNotScheduleStructuralPersistence() async throws {
        let container = try makeInMemoryContainer()
        let profileId = UUID()
        let spaceAId = UUID()
        let spaceBId = UUID()
        let selectedTabId = UUID()
        let firstTabId = UUID()
        let folderFirstId = UUID()
        let folderSecondId = UUID()
        let pinnedFirstId = UUID()
        let pinnedSecondId = UUID()
        let spacePinnedFirstId = UUID()
        let spacePinnedSecondId = UUID()

        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(
                id: spaceAId,
                name: "A",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                index: 1,
                profileId: profileId
            )
        )
        mutationContext.insert(
            SpaceEntity(
                id: spaceBId,
                name: "B",
                icon: "🏠",
                index: 0,
                profileId: profileId
            )
        )
        mutationContext.insert(
            FolderEntity(
                id: folderSecondId,
                name: "Later",
                icon: "zen:book",
                color: "#111111",
                spaceId: spaceAId,
                isOpen: false,
                index: 1
            )
        )
        mutationContext.insert(
            FolderEntity(
                id: folderFirstId,
                name: "First",
                icon: "zen:bookmark",
                color: "#222222",
                spaceId: spaceAId,
                isOpen: true,
                index: 0
            )
        )
        mutationContext.insert(
            TabEntity(
                id: pinnedSecondId,
                urlString: "https://example.com/pinned-second",
                name: "Pinned Second",
                isPinned: true,
                index: 1,
                spaceId: nil,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: pinnedFirstId,
                urlString: "https://example.com/pinned-first",
                name: "Pinned First",
                isPinned: true,
                index: 0,
                spaceId: nil,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: spacePinnedSecondId,
                urlString: "https://example.com/space-pinned-second",
                name: "Space Pinned Second",
                isPinned: false,
                isSpacePinned: true,
                index: 1,
                spaceId: spaceAId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: spacePinnedFirstId,
                urlString: "https://example.com/space-pinned-first",
                name: "Space Pinned First",
                isPinned: false,
                isSpacePinned: true,
                index: 0,
                spaceId: spaceAId,
                folderId: folderFirstId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: selectedTabId,
                urlString: "https://example.com/selected",
                name: "Selected",
                isPinned: false,
                index: 1,
                spaceId: spaceAId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: firstTabId,
                urlString: "https://example.com/first",
                name: "First",
                isPinned: false,
                index: 0,
                spaceId: spaceAId
            )
        )
        mutationContext.insert(TabsStateEntity(currentTabID: selectedTabId, currentSpaceID: spaceAId))
        try mutationContext.save()

        let tabManager = makeTabManager(context: ModelContext(container))
        let didLoad = await tabManager.storeRestore.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [spaceBId, spaceAId])
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[spaceAId]?.map(\.id), [firstTabId, selectedTabId])
        XCTAssertEqual(tabManager.folderCollectionStateOwner.folders(for: spaceAId).map(\.id), [folderFirstId, folderSecondId])
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .pinnedByProfileSnapshot()[profileId]?.map(\.id),
            [pinnedFirstId, pinnedSecondId]
        )
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceAId).map(\.id),
            [spacePinnedFirstId, spacePinnedSecondId]
        )
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, spaceAId)
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, selectedTabId)
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)
    }

    func testStartupRestoreRepairsMalformedPersistedStateAfterMainApply() async throws {
        let container = try makeInMemoryContainer()
        let profileId = UUID()
        let validSpaceId = UUID()
        let missingSpaceId = UUID()
        let validTabId = UUID()
        let orphanTabId = UUID()
        let orphanFolderId = UUID()
        let missingFolderId = UUID()
        let folderChildPinId = UUID()
        let noSpacePinId = UUID()

        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(
                id: validSpaceId,
                name: "Valid",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                index: 0,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: validTabId,
                urlString: "https://example.com/valid",
                name: "Valid",
                isPinned: false,
                index: 0,
                spaceId: validSpaceId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: orphanTabId,
                urlString: "https://example.com/orphan",
                name: "Orphan",
                isPinned: false,
                index: 1,
                spaceId: missingSpaceId
            )
        )
        mutationContext.insert(
            FolderEntity(
                id: orphanFolderId,
                name: "Orphan Folder",
                icon: "zen:book",
                color: "#333333",
                spaceId: missingSpaceId,
                isOpen: false,
                index: 0
            )
        )
        mutationContext.insert(
            TabEntity(
                id: folderChildPinId,
                urlString: "https://example.com/folder-child",
                name: "Folder Child",
                isPinned: false,
                isSpacePinned: true,
                index: 0,
                spaceId: validSpaceId,
                folderId: missingFolderId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: noSpacePinId,
                urlString: "https://example.com/no-space",
                name: "No Space",
                isPinned: false,
                isSpacePinned: true,
                index: 1,
                spaceId: nil
            )
        )
        mutationContext.insert(TabsStateEntity(currentTabID: UUID(), currentSpaceID: missingSpaceId))
        try mutationContext.save()

        let tabManager = makeTabManager(context: ModelContext(container))
        let didLoad = await tabManager.storeRestore.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, validSpaceId)
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, validTabId)
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[validSpaceId]?.map(\.id), [validTabId])
        let repairedPin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: validSpaceId).first)
        XCTAssertEqual(repairedPin.id, folderChildPinId)
        XCTAssertNil(repairedPin.folderId)
        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.spacePinnedShortcutsSnapshot()[missingSpaceId])
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)

        try await waitForStore(in: container) { context in
            let repairedStoredPin = try fetchTab(folderChildPinId, in: context)
            let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first
            return try fetchTab(orphanTabId, in: context) == nil
                && fetchFolder(orphanFolderId, in: context) == nil
                && fetchTab(noSpacePinId, in: context) == nil
                && repairedStoredPin?.folderId == nil
                && state?.currentSpaceID == validSpaceId
                && state?.currentTabID == validTabId
        }
    }

    func testStartupRestoreNormalizesLauncherIconAssetsAndPersistsRepair() async throws {
        let container = try makeInMemoryContainer()
        let profileId = UUID()
        let spaceId = UUID()
        let pinnedId = UUID()
        let spacePinnedId = UUID()

        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(
                id: spaceId,
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                index: 0,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: pinnedId,
                urlString: "https://example.com/pinned",
                name: "Pinned",
                isPinned: true,
                index: 0,
                spaceId: nil,
                profileId: profileId,
                iconAsset: "   "
            )
        )
        mutationContext.insert(
            TabEntity(
                id: spacePinnedId,
                urlString: "https://example.com/space-pinned",
                name: "Space Pinned",
                isPinned: false,
                isSpacePinned: true,
                index: 0,
                spaceId: spaceId,
                iconAsset: "   "
            )
        )
        mutationContext.insert(TabsStateEntity(currentTabID: nil, currentSpaceID: spaceId))
        try mutationContext.save()

        let tabManager = makeTabManager(context: ModelContext(container))
        let didLoad = await tabManager.storeRestore.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertNil(
            tabManager.shortcutPinCollectionStateOwner
                .pinnedByProfileSnapshot()[profileId]?.first?.iconAsset
        )
        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId).first?.iconAsset)
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)

        try await waitForStore(in: container) { context in
            try fetchTab(pinnedId, in: context)?.iconAsset == nil
                && fetchTab(spacePinnedId, in: context)?.iconAsset == nil
        }
    }

    func testStartupRestoreCurrentFormatDoesNotDuplicateAcrossRepeatedLoads() async throws {
        let container = try makeInMemoryContainer()
        let fixture = try insertCurrentFormatRestoreFixture(in: container)
        let tabManager = makeTabManager(context: ModelContext(container))

        let firstLoad = await tabManager.storeRestore.loadFromStoreAwaitingResult()
        XCTAssertTrue(firstLoad)
        try await waitPastStructuralDebounce()

        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [fixture.spaceAId, fixture.spaceBId])
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[fixture.spaceAId]?.map(\.id), [fixture.firstTabId, fixture.secondTabId])
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, fixture.spaceAId)
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, fixture.secondTabId)
        try assertStoreShape(in: container, spaces: 2, folders: 1, tabs: 4)

        let secondLoad = await tabManager.storeRestore.loadFromStoreAwaitingResult()
        XCTAssertTrue(secondLoad)
        try await waitPastStructuralDebounce()

        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [fixture.spaceAId, fixture.spaceBId])
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[fixture.spaceAId]?.map(\.id), [fixture.firstTabId, fixture.secondTabId])
        try assertStoreShape(in: container, spaces: 2, folders: 1, tabs: 4)
    }

    func testPostRestoreStructuralMutationPersistsOnceWithoutDuplicatingRestoredGraph() async throws {
        let container = try makeInMemoryContainer()
        let fixture = try insertCurrentFormatRestoreFixture(in: container)
        let tabManager = makeTabManager(context: ModelContext(container))

        let didLoad = await tabManager.storeRestore.loadFromStoreAwaitingResult()
        XCTAssertTrue(didLoad)
        try await waitPastStructuralDebounce()

        let restoredSpace = try XCTUnwrap(tabManager.spaceStateOwner.spaces.first { $0.id == fixture.spaceAId })
        let created = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/post-restore",
            in: restoredSpace,
            activate: false
        )

        try await waitForStore(in: container) { context in
            try fetchTab(created.id, in: context) != nil
        }
        XCTAssertNotNil(try fetchTab(created.id, in: ModelContext(container)))
        try assertStoreShape(in: container, spaces: 2, folders: 1, tabs: 5)
    }

    func testStructuralTransactionPersistsFinalOrderOnce() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Batch", profileId: UUID())
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/three", in: space, activate: false)

        try await waitForStore(in: container) { context in
            try fetchTab(first.id, in: context) != nil
                && (try fetchTab(second.id, in: context)) != nil
                && (try fetchTab(third.id, in: context)) != nil
        }

        tabManager.structuralLookupCoordinator.withTransaction {
            tabManager.regularTabCollectionOwner.reorderRegularTabs(first, in: space.id, to: 3)
            tabManager.regularTabCollectionOwner.reorderRegularTabs(second, in: space.id, to: 3)
        }

        try await waitForStore(in: container) { context in
            try fetchTab(third.id, in: context)?.index == 0
                && (try fetchTab(first.id, in: context))?.index == 1
                && (try fetchTab(second.id, in: context))?.index == 2
        }
        XCTAssertEqual(try fetchTab(third.id, in: ModelContext(container))?.index, 0)
        XCTAssertEqual(try fetchTab(first.id, in: ModelContext(container))?.index, 1)
        XCTAssertEqual(try fetchTab(second.id, in: ModelContext(container))?.index, 2)
    }

    private func makeTabManager(context: ModelContext) -> TabManager {
        let tabManager = TabManager(context: context, loadPersistedState: false)
        tabManager.runtimePortsAttachmentOwner.attach(TestRuntimePorts.inactive)
        return tabManager
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private struct CurrentFormatRestoreFixture {
        let profileId: UUID
        let spaceAId: UUID
        let spaceBId: UUID
        let folderId: UUID
        let firstTabId: UUID
        let secondTabId: UUID
        let pinnedTabId: UUID
        let spacePinnedTabId: UUID
    }

    private func insertCurrentFormatRestoreFixture(
        in container: ModelContainer
    ) throws -> CurrentFormatRestoreFixture {
        let fixture = CurrentFormatRestoreFixture(
            profileId: UUID(),
            spaceAId: UUID(),
            spaceBId: UUID(),
            folderId: UUID(),
            firstTabId: UUID(),
            secondTabId: UUID(),
            pinnedTabId: UUID(),
            spacePinnedTabId: UUID()
        )
        let context = ModelContext(container)
        context.insert(
            SpaceEntity(
                id: fixture.spaceAId,
                name: "A",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                index: 0,
                profileId: fixture.profileId
            )
        )
        context.insert(
            SpaceEntity(
                id: fixture.spaceBId,
                name: "B",
                icon: "🏠",
                index: 1,
                profileId: fixture.profileId
            )
        )
        context.insert(
            FolderEntity(
                id: fixture.folderId,
                name: "Docs",
                icon: "zen:book",
                color: "#111111",
                spaceId: fixture.spaceAId,
                isOpen: true,
                index: 0
            )
        )
        context.insert(
            TabEntity(
                id: fixture.firstTabId,
                urlString: "https://example.com/one",
                name: "One",
                isPinned: false,
                index: 0,
                spaceId: fixture.spaceAId
            )
        )
        context.insert(
            TabEntity(
                id: fixture.secondTabId,
                urlString: "https://example.com/two",
                name: "Two",
                isPinned: false,
                index: 1,
                spaceId: fixture.spaceAId
            )
        )
        context.insert(
            TabEntity(
                id: fixture.pinnedTabId,
                urlString: "https://example.com/pinned",
                name: "Pinned",
                isPinned: true,
                index: 0,
                spaceId: nil,
                profileId: fixture.profileId
            )
        )
        context.insert(
            TabEntity(
                id: fixture.spacePinnedTabId,
                urlString: "https://example.com/space-pinned",
                name: "Space Pinned",
                isPinned: false,
                isSpacePinned: true,
                index: 0,
                spaceId: fixture.spaceAId,
                folderId: fixture.folderId
            )
        )
        context.insert(
            TabsStateEntity(
                currentTabID: fixture.secondTabId,
                currentSpaceID: fixture.spaceAId
            )
        )
        try context.save()
        return fixture
    }

    private func fetchTab(_ id: UUID, in context: ModelContext) throws -> TabEntity? {
        let tabId = id
        let predicate = #Predicate<TabEntity> { $0.id == tabId }
        return try context.fetch(FetchDescriptor<TabEntity>(predicate: predicate)).first
    }

    private func fetchFolder(_ id: UUID, in context: ModelContext) throws -> FolderEntity? {
        let folderId = id
        let predicate = #Predicate<FolderEntity> { $0.id == folderId }
        return try context.fetch(FetchDescriptor<FolderEntity>(predicate: predicate)).first
    }

    private func fetchSpace(_ id: UUID, in context: ModelContext) throws -> SpaceEntity? {
        let spaceId = id
        let predicate = #Predicate<SpaceEntity> { $0.id == spaceId }
        return try context.fetch(FetchDescriptor<SpaceEntity>(predicate: predicate)).first
    }

    private func fetchSpacesSortedByIndex(in context: ModelContext) throws -> [SpaceEntity] {
        try context.fetch(FetchDescriptor<SpaceEntity>()).sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func assertStoreShape(
        in container: ModelContainer,
        spaces expectedSpaces: Int,
        folders expectedFolders: Int,
        tabs expectedTabs: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let context = ModelContext(container)
        let spaces = try context.fetch(FetchDescriptor<SpaceEntity>())
        let folders = try context.fetch(FetchDescriptor<FolderEntity>())
        let tabs = try context.fetch(FetchDescriptor<TabEntity>())

        XCTAssertEqual(spaces.count, expectedSpaces, file: file, line: line)
        XCTAssertEqual(folders.count, expectedFolders, file: file, line: line)
        XCTAssertEqual(tabs.count, expectedTabs, file: file, line: line)
        XCTAssertEqual(Set(spaces.map(\.id)).count, spaces.count, file: file, line: line)
        XCTAssertEqual(Set(folders.map(\.id)).count, folders.count, file: file, line: line)
        XCTAssertEqual(Set(tabs.map(\.id)).count, tabs.count, file: file, line: line)
    }

    private func waitForPersistedState(
        in container: ModelContainer,
        matching predicate: (TabsStateEntity) throws -> Bool
    ) async throws {
        for _ in 0..<50 {
            let context = ModelContext(container)
            if let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first,
               try predicate(state) {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let context = ModelContext(container)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<TabsStateEntity>()).first)
        XCTAssertTrue(try predicate(state))
    }

    private func waitForStore(
        in container: ModelContainer,
        file: StaticString = #filePath,
        line: UInt = #line,
        matching predicate: (ModelContext) throws -> Bool
    ) async throws {
        for _ in 0..<50 {
            let context = ModelContext(container)
            if try predicate(context) {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let context = ModelContext(container)
        XCTAssertTrue(try predicate(context), file: file, line: line)
    }

    private func waitPastStructuralDebounce() async throws {
        try await Task.sleep(nanoseconds: 350_000_000)
    }
}
