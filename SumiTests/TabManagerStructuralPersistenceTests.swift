import SumiDomain
import SumiWebRuntime
import SwiftData
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
private final class DeferredPersistenceSpaceTransition:
    TabWebViewProfileTransitionParticipant {
    private(set) var stageModel: (@MainActor @Sendable () -> Bool)?
    private(set) var finishModel: (() -> Void)?
    private(set) var settlement: ProfileTransitionService.Settlement?

    func makeLifecycle() -> TabManagerWebViewLifecycleService {
        TestRuntimePorts.webViewLifecycle(
            retirement: .rejecting,
            anyLiveWebView: { $0.resolvedCurrentWebView() },
            profileTransitions: self
        )
    }

    func abortProfileTransitions(profileIDs: Set<UUID>) -> Int { 0 }

    func executeProfileAssignment(
        for tab: Tab,
        targetProfile: Profile,
        intent: DeferredWebViewProfileAssignmentIntent,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        settlement(.rejected(.failed))
        return .failed
    }

    func executePreparedProfileAssignments(
        _ assignments: [PreparedTabProfileAssignment],
        bindingModel: any ShortcutTabBindingAggregateTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> PreparedProfileAssignmentBatchTransitionOutcome {
        let model = PreparedProfileAssignmentBatchModelTransaction(
            assignments: assignments,
            binding: bindingModel
        )
        guard model.validateForStaging() else {
            settlement(.rejected(.stale))
            return .rejectedUnstaged(.stale)
        }
        let outcome = ProfileTransitionModelOnlySettlement.execute(
            .transaction(model)
        )
        settlement(outcome.settlement)
        return outcome.batchExecution
    }

    func executeSpaceProfileAssignment(
        space: Space,
        targetProfile: Profile,
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        model: any SpaceProfileWebViewReplacementTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        stageModel = {
            do {
                try model.stage()
                return true
            } catch {
                return false
            }
        }
        finishModel = {
            precondition(model.stagedModelIsExact())
            precondition(model.canClaimTerminalModel())
            precondition(model.claimTerminalModel() == .sealed)
            model.publishCommit()
        }
        self.settlement = settlement
        return .deferred
    }
}

@MainActor
final class TabManagerStructuralPersistenceTests: XCTestCase {
    func testStartupRestoreRequestedAtConstructionCannotOverwritePreReadinessMutation() async throws {
        let container = try makeInMemoryContainer()
        let persistedFixture = try insertCurrentFormatRestoreFixture(in: container)
        let tabManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: container
            ),
            automaticallyStartPersistedStateLoad: false
        )
        let webViewSessions = tabManager.webViewSessions
        let runtimeLifecycle = tabManager.tabRuntimeLifecycle

        let liveSpace = try makeSpace(
            in: tabManager,
            name: "Created Before Shell Readiness",
            profileID: persistedFixture.profileId
        )
        let liveTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/pre-readiness",
            in: liveSpace,
            activate: true
        )

        runtimeLifecycle.startPersistedStateRestoreIfNeeded()
        for _ in 0..<50
        where tabManager.startupRestoreLifecycle.hasLoadedInitialData == false {
            await Task.yield()
        }

        XCTAssertTrue(tabManager.startupRestoreLifecycle.didStartPersistedStateLoad)
        XCTAssertTrue(tabManager.startupRestoreLifecycle.hasLoadedInitialData)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [liveSpace.id])
        XCTAssertEqual(
            tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[liveSpace.id]?.map(\.id),
            [liveTab.id]
        )
        XCTAssertFalse(tabManager.spaceStateOwner.spaces.contains { $0.id == persistedFixture.spaceAId })
        XCTAssertTrue(liveTab.webViewSession.isBacked(by: webViewSessions))
    }

    func testStartupRestoreDoesNotOverwriteTabCreatedWhileSnapshotLoadIsSuspended() async throws {
        let container = try makeInMemoryContainer()
        let persistedFixture = try insertCurrentFormatRestoreFixture(in: container)
        let payloadLoader = SuspendedTabRestorePayloadLoader(container: container)
        let tabManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: container
            ),
            automaticallyStartPersistedStateLoad: false
        )
        let webViewSessions = tabManager.webViewSessions
        let payloadApplier = TabRestorePayloadApplyService(
            tabFactory: tabManager.tabFactory,
            structuralInstaller: tabManager.structuralInstallOwner,
            runtimePreparation: TabRuntimePreparationOwner(
                runtimeConnection: tabManager.runtimePortConnection
            ),
            lazyRestore: tabManager.lazyRestoreCoordinator,
            persistence: tabManager.structuralPersistence
        )
        let restoreService = TabStoreRestoreService(
            runtimeConnection: tabManager.runtimePortConnection,
            structuralLookup: tabManager.structuralLookupCoordinator,
            loadLifecycle: tabManager.startupRestoreLifecycle,
            executor: TabStoreRestoreAttemptExecutor(
                payloadLoader: payloadLoader,
                structuralStore: TabStructuralSnapshotStore(
                    writes: TabStoreWriteExecutor(container: container)
                ),
                structuralLookup: tabManager.structuralLookupCoordinator,
                loadLifecycle: tabManager.startupRestoreLifecycle,
                payloadApplier: payloadApplier
            )
        )

        let restoreTask = Task { @MainActor in
            await restoreService.loadFromStoreAwaitingResult()
        }
        await payloadLoader.waitUntilPayloadIsCaptured()

        let liveSpace = try makeSpace(
            in: tabManager,
            name: "Created During Restore",
            profileID: persistedFixture.profileId
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
            tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[liveSpace.id]?.map(\.id),
            [liveTab.id]
        )
        XCTAssertTrue(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id) === liveTab)
        XCTAssertTrue(liveTab.webViewSession.isBacked(by: webViewSessions))
        XCTAssertTrue(liveTab.webViewSession.untrackedWebView === liveWebView)
        XCTAssertFalse(tabManager.spaceStateOwner.spaces.contains { $0.id == persistedFixture.spaceAId })

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
            try fetchTab(liveTab.id, in: context) != nil
        }
    }

    func testIncrementalAddAndRemoveRegularTabPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = try makeSpace(in: tabManager, name: "Work")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: true)

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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

        tabManager.tabClosureService.removeTab(tab.id)
        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
            try fetchTab(tab.id, in: context) == nil
        }

        context = ModelContext(container)
        XCTAssertNil(try fetchTab(tab.id, in: context))
    }

    func testCommittedInFlightFollowerReloadsAsSpaceInherited() async throws {
        let container = try makeInMemoryContainer()
        let profile = Profile(name: "Pending")
        let transition = DeferredPersistenceSpaceTransition()
        let tabManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: container
            ),
            runtimePorts: TestRuntimePorts.make(
                currentProfileId: { profile.id },
                defaultProfileId: { profile.id },
                profile: { $0 == profile.id ? profile : nil },
                webViewLifecycle: transition.makeLifecycle()
            ),
            automaticallyStartPersistedStateLoad: false
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
        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
            try fetchTab(follower.id, in: context)?.profileId == profile.id
        }

        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.finishModel)()
        try XCTUnwrap(transition.settlement)(.committed)

        XCTAssertNil(follower.profileId)
        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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
        let space = try makeSpace(in: tabManager, name: "Work")
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

        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, extensionTab.id)

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
        let space = try makeSpace(in: tabManager, name: "Work")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/start",
            in: space,
            activate: true
        )

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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
        let didLoad = await makeStoreRestore(for: tabManager)
            .loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[spaceId]?.map(\.id), [normalTabId])
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, spaceId)
        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, normalTabId)

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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
        let retirement = DeferredSpaceProfileTransition()
        let tabManager = makeTabManager(
            context: container.mainContext,
            webViewLifecycle: retirement.makeLifecycle()
        )
        let space = try makeSpace(in: tabManager, name: "Pinned")
        let folder = try XCTUnwrap(
            tabManager.sidebarFolderCommands.createFolder(
                in: space.id,
                name: "Docs"
            )
        )
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/docs", in: space, activate: true)

        tabManager.sidebarRegularTabPlacementCommands.moveTabToFolder(
            tab,
            folderID: folder.id
        )
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).first)

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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

        XCTAssertTrue(tabManager.sidebarFolderCommands.ungroupFolder(folder.id))
        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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
        let retirement = DeferredSpaceProfileTransition()
        let tabManager = makeTabManager(
            context: container.mainContext,
            webViewLifecycle: retirement.makeLifecycle()
        )
        let space = try makeSpace(in: tabManager, name: "Pinned")
        let folder = try XCTUnwrap(
            tabManager.sidebarFolderCommands.createFolder(
                in: space.id,
                name: "Docs"
            )
        )
        let nested = try XCTUnwrap(
            tabManager.sidebarFolderCommands.createFolder(
                in: space.id,
                parentFolderID: folder.id,
                name: "Nested"
            )
        )
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/docs", in: space, activate: true)
        let nestedTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/nested", in: space, activate: false)

        tabManager.sidebarRegularTabPlacementCommands.moveTabToFolder(
            tab,
            folderID: folder.id
        )
        tabManager.sidebarRegularTabPlacementCommands.moveTabToFolder(
            nestedTab,
            folderID: nested.id
        )
        let pins = tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id)
        let pinIds = Set(pins.map(\.id))
        XCTAssertEqual(pins.count, 2)

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
            try fetchFolder(folder.id, in: context) != nil
                && fetchFolder(nested.id, in: context) != nil
                && pins.allSatisfy { pin in
                    (try? fetchTab(pin.id, in: context)) != nil
                }
        }

        XCTAssertTrue(tabManager.sidebarFolderCommands.deleteFolder(folder.id))
        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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
        let space = try makeSpace(in: tabManager, name: "Pinned")
        let folder = try XCTUnwrap(
            tabManager.sidebarFolderCommands.createFolder(
                in: space.id,
                name: "Docs"
            )
        )

        tabManager.folderOpenState.setFolder(folder.id, open: true)
        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
            try fetchFolder(folder.id, in: context)?.isOpen == true
        }

        tabManager.folderOpenState.setFolder(folder.id, open: false)
        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
            try fetchFolder(folder.id, in: context)?.isOpen == false
        }
    }

    func testTopLevelFolderPositionPersistsAfterSpacePinnedShortcuts() async throws {
        let container = try makeInMemoryContainer()
        let retirement = DeferredSpaceProfileTransition()
        let tabManager = makeTabManager(
            context: container.mainContext,
            webViewLifecycle: retirement.makeLifecycle()
        )
        let space = try makeSpace(in: tabManager, name: "Pinned")
        let firstPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://example.com/first")),
            title: "First"
        )
        let secondPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 1,
            launchURL: try XCTUnwrap(URL(string: "https://example.com/second")),
            title: "Second"
        )
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([firstPin, secondPin], for: space.id)
        let folder = try XCTUnwrap(
            tabManager.sidebarFolderCommands.createFolder(
                in: space.id,
                name: "Bottom"
            )
        )

        XCTAssertEqual(
            tabManager.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: space.id).map(\.id),
            [firstPin.id, secondPin.id, folder.id]
        )

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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
        let didLoad = await makeStoreRestore(for: restoredManager)
            .loadFromStoreAwaitingResult()

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
        let spaceA = try makeSpace(in: tabManager, name: "A", profileID: profileId)
        let tabA = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/a", in: spaceA, activate: true)
        _ = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/a2", in: spaceA, activate: false)
        let spaceB = try makeSpace(in: tabManager, name: "B", profileID: profileId)
        let tabB = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/b", in: spaceB, activate: true)

        tabManager.sidebarDragRouter.moveTab(tabA.id, to: spaceB.id)
        tabManager.regularTabCollectionOwner.reorderRegularTabs(tabA, in: spaceB.id, to: 0)

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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
        let first = try makeSpace(in: tabManager, name: "First", profileID: profileId)
        let second = try makeSpace(in: tabManager, name: "Second", profileID: profileId)
        let third = try makeSpace(in: tabManager, name: "Third", profileID: profileId)
        tabManager.spaceActivation.setActiveSpace(second)

        XCTAssertTrue(tabManager.sidebarSpaceLifecycle.reorderSpace(first.id, to: 2))
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, second.id)

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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
        let first = try makeSpace(in: tabManager, name: "First", profileID: profileId)
        let second = try makeSpace(in: tabManager, name: "Second", profileID: profileId)
        let third = try makeSpace(in: tabManager, name: "Third", profileID: profileId)
        tabManager.spaceActivation.setActiveSpace(second)

        XCTAssertTrue(tabManager.sidebarSpaceLifecycle.reorderSpace(first.id, to: 2))

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
            try fetchSpacesSortedByIndex(in: context).map(\.id) == [second.id, third.id, first.id]
        }

        let restoredManager = makeTabManager(context: ModelContext(container))
        let didLoad = await makeStoreRestore(for: restoredManager)
            .loadFromStoreAwaitingResult()

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
        let first = try makeSpace(in: tabManager, name: "First", profileID: profileId)
        let second = try makeSpace(in: tabManager, name: "Second", profileID: profileId)
        let third = try makeSpace(in: tabManager, name: "Third", profileID: profileId)

        XCTAssertTrue(tabManager.sidebarSpaceLifecycle.reorderSpace(third.id, to: -100))
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [third.id, first.id, second.id])
        XCTAssertTrue(tabManager.sidebarSpaceLifecycle.reorderSpace(third.id, to: 100))
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [first.id, second.id, third.id])
        XCTAssertFalse(tabManager.sidebarSpaceLifecycle.reorderSpace(UUID(), to: 0))
    }

    func testSelectionOnlyPersistenceCreatesAndUpdatesState() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = try makeSpace(in: tabManager, name: "Select")
        _ = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space, activate: true)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)

        try await waitForPersistedState(in: container, after: tabManager.structuralPersistence) { state in
            state.currentSpaceID == space.id
        }
        tabManager.activeSelectionOwner.setActiveTab(second)

        try await waitForPersistedState(in: container, after: tabManager.structuralPersistence) { state in
            state.currentTabID == second.id && state.currentSpaceID == space.id
        }
    }

    func testActiveTabStatePathsPersistSelectionWithoutSchedulingStructuralPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let profileId = UUID()
        let firstSpace = try makeSpace(in: tabManager, name: "First", profileID: profileId)
        let secondSpace = try makeSpace(in: tabManager, name: "Second", profileID: profileId)
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/first", in: firstSpace, activate: false)
        let alternate = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/alternate", in: firstSpace, activate: false)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/second", in: secondSpace, activate: false)

        tabManager.activeSelectionOwner.setActiveTab(first)
        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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

        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, second.id)
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, secondSpace.id)
        XCTAssertEqual(secondSpace.activeTabId, second.id)
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)
        try await waitForPersistedState(in: container, after: tabManager.structuralPersistence) { state in
            state.currentTabID == second.id && state.currentSpaceID == secondSpace.id
        }

        tabManager.activeSelectionOwner.updateActiveTabState(alternate)

        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, alternate.id)
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, firstSpace.id)
        XCTAssertEqual(firstSpace.activeTabId, alternate.id)
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)
        try await waitForPersistedState(in: container, after: tabManager.structuralPersistence) { state in
            state.currentTabID == alternate.id && state.currentSpaceID == firstSpace.id
        }
    }

    func testRuntimeStateBatchFlushUpdatesStoredTabFields() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = try makeSpace(in: tabManager, name: "Runtime")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/initial", in: space, activate: true)

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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
        let space = try makeSpace(in: tabManager, name: "Split")
        let tabs = [
            tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space, activate: true),
            tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false),
            tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/three", in: space, activate: false),
        ]
        let baseGroup = try XCTUnwrap(
            SplitGroup.make(
                members: tabs.map { .regularTab($0.id) },
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )
        let resizedGroup = try XCTUnwrap(
            baseGroup.replacingLayoutTree(
                with: SplitLayoutSizing.updatingChildWeights(
                    in: baseGroup.layoutTree,
                    at: [],
                    weights: [0.2, 0.3, 0.5]
                )
            )
        )

        XCTAssertTrue(tabManager.splitGroupMutations.insert(resizedGroup))

        try await waitForPersistedState(in: container, after: tabManager.structuralPersistence) { state in
            guard let data = state.splitGroupsData,
                  let archive = try? TabPersistenceCodec()
                    .decodeSplitGroupArchive(from: data),
                  let storedGroup = archive.groups.first(where: { $0.id == resizedGroup.id })
            else {
                return false
            }
            return storedGroup.layoutKind == resizedGroup.layoutKind
                && storedGroup.layoutTree == resizedGroup.layoutTree
                && storedGroup.container == resizedGroup.container
        }

        let restoredManager = makeTabManager(context: ModelContext(container))
        let didLoad = await makeStoreRestore(for: restoredManager)
            .loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        let restoredGroup = try XCTUnwrap(
            restoredManager.splitGroupStore.group(id: resizedGroup.id)
        )
        XCTAssertEqual(restoredGroup.layoutKind, resizedGroup.layoutKind)
        XCTAssertEqual(restoredGroup.layoutTree, resizedGroup.layoutTree)
        XCTAssertEqual(restoredGroup.container, resizedGroup.container)
    }

    func testShortcutBackedSplitGroupPersistsThroughStoreReload() async throws {
        let container = try makeInMemoryContainer()
        let retirement = DeferredSpaceProfileTransition()
        let tabManager = makeTabManager(
            context: container.mainContext,
            webViewLifecycle: retirement.makeLifecycle()
        )
        let space = try makeSpace(in: tabManager, name: "Split")
        let regular = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/regular", in: space, activate: true)
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://example.com/pinned")),
            title: "Pinned"
        )
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: space.id)
        let windowId = UUID()
        let livePinnedTab = tabManager.shortcutTabMaterializer.materialize(pin, in: windowId, currentSpaceId: space.id)!
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .regularTab(regular.id),
                    .shortcutPin(pin.id),
                ],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group))

        try await waitForPersistedState(in: container, after: tabManager.structuralPersistence) { state in
            guard let data = state.splitGroupsData,
                  let archive = try? TabPersistenceCodec()
                    .decodeSplitGroupArchive(from: data)
            else {
                return false
            }
            return archive.groups.contains {
                $0.id == group.id && $0.contains(.shortcutPin(pin.id))
            }
        }

        let restoredManager = makeTabManager(context: ModelContext(container))
        let didLoad = await makeStoreRestore(for: restoredManager)
            .loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        let restoredGroup = try XCTUnwrap(
            restoredManager.splitGroupStore.group(
                containing: .shortcutPin(pin.id)
            )
        )
        XCTAssertEqual(restoredGroup.id, group.id)
        XCTAssertTrue(restoredGroup.contains(.regularTab(regular.id)))
        XCTAssertTrue(restoredGroup.contains(.shortcutPin(pin.id)))
        XCTAssertFalse(restoredGroup.contains(.regularTab(livePinnedTab.id)))
    }

    func testFullReconcileDeletesStaleEntitiesAndPreservesFolders() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = try makeSpace(in: tabManager, name: "Clean")
        let folder = try XCTUnwrap(
            tabManager.sidebarFolderCommands.createFolder(
                in: space.id,
                name: "Keep"
            )
        )
        _ = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/keep", in: space, activate: true)
        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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
        let didLoad = await makeStoreRestore(for: tabManager)
            .loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [spaceBId, spaceAId])
        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[spaceAId]?.map(\.id), [firstTabId, selectedTabId])
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
        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, selectedTabId)
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
        let didLoad = await makeStoreRestore(for: tabManager)
            .loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, validSpaceId)
        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, validTabId)
        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[validSpaceId]?.map(\.id), [validTabId])
        let repairedPin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: validSpaceId).first)
        XCTAssertEqual(repairedPin.id, folderChildPinId)
        XCTAssertNil(repairedPin.folderId)
        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.spacePinnedShortcutsSnapshot()[missingSpaceId])
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
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
        let didLoad = await makeStoreRestore(for: tabManager)
            .loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertNil(
            tabManager.shortcutPinCollectionStateOwner
                .pinnedByProfileSnapshot()[profileId]?.first?.iconAsset
        )
        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId).first?.iconAsset)
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
            try fetchTab(pinnedId, in: context)?.iconAsset == nil
                && fetchTab(spacePinnedId, in: context)?.iconAsset == nil
        }
    }

    func testStartupRestoreCurrentFormatDoesNotDuplicateAcrossRepeatedLoads() async throws {
        let container = try makeInMemoryContainer()
        let fixture = try insertCurrentFormatRestoreFixture(in: container)
        let tabManager = makeTabManager(context: ModelContext(container))

        let firstLoad = await makeStoreRestore(for: tabManager)
            .loadFromStoreAwaitingResult()
        XCTAssertTrue(firstLoad)
        await awaitStructuralPersistence(tabManager.structuralPersistence)

        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [fixture.spaceAId, fixture.spaceBId])
        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[fixture.spaceAId]?.map(\.id), [fixture.firstTabId, fixture.secondTabId])
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpace?.id, fixture.spaceAId)
        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, fixture.secondTabId)
        try assertStoreShape(in: container, spaces: 2, folders: 1, tabs: 4)

        let secondLoad = await makeStoreRestore(for: tabManager)
            .loadFromStoreAwaitingResult()
        XCTAssertTrue(secondLoad)
        await awaitStructuralPersistence(tabManager.structuralPersistence)

        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [fixture.spaceAId, fixture.spaceBId])
        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[fixture.spaceAId]?.map(\.id), [fixture.firstTabId, fixture.secondTabId])
        try assertStoreShape(in: container, spaces: 2, folders: 1, tabs: 4)
    }

    func testPostRestoreStructuralMutationPersistsOnceWithoutDuplicatingRestoredGraph() async throws {
        let container = try makeInMemoryContainer()
        let fixture = try insertCurrentFormatRestoreFixture(in: container)
        let tabManager = makeTabManager(context: ModelContext(container))

        let didLoad = await makeStoreRestore(for: tabManager)
            .loadFromStoreAwaitingResult()
        XCTAssertTrue(didLoad)
        await awaitStructuralPersistence(tabManager.structuralPersistence)

        let restoredSpace = try XCTUnwrap(tabManager.spaceStateOwner.spaces.first { $0.id == fixture.spaceAId })
        let created = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/post-restore",
            in: restoredSpace,
            activate: false
        )

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
            try fetchTab(created.id, in: context) != nil
        }
        XCTAssertNotNil(try fetchTab(created.id, in: ModelContext(container)))
        try assertStoreShape(in: container, spaces: 2, folders: 1, tabs: 5)
    }

    func testStructuralTransactionPersistsFinalOrderOnce() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = makeTabManager(context: container.mainContext)
        let space = try makeSpace(in: tabManager, name: "Batch")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/three", in: space, activate: false)

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
            try fetchTab(first.id, in: context) != nil
                && (try fetchTab(second.id, in: context)) != nil
                && (try fetchTab(third.id, in: context)) != nil
        }

        tabManager.structuralLookupCoordinator.withTransaction {
            tabManager.regularTabCollectionOwner.reorderRegularTabs(first, in: space.id, to: 3)
            tabManager.regularTabCollectionOwner.reorderRegularTabs(second, in: space.id, to: 3)
        }

        try await waitForStore(in: container, after: tabManager.structuralPersistence) { context in
            try fetchTab(third.id, in: context)?.index == 0
                && (try fetchTab(first.id, in: context))?.index == 1
                && (try fetchTab(second.id, in: context))?.index == 2
        }
        XCTAssertEqual(try fetchTab(third.id, in: ModelContext(container))?.index, 0)
        XCTAssertEqual(try fetchTab(first.id, in: ModelContext(container))?.index, 1)
        XCTAssertEqual(try fetchTab(second.id, in: ModelContext(container))?.index, 2)
    }

    private func makeTabManager(
        context: ModelContext,
        webViewLifecycle: TabManagerWebViewLifecycleService? = nil
    ) -> BrowserManager {
        let tabManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: context.container
            ),
            runtimePorts: webViewLifecycle.map {
                TestRuntimePorts.make(webViewLifecycle: $0)
            } ?? TestRuntimePorts.inactive,
            automaticallyStartPersistedStateLoad: false
        )
        return tabManager
    }

    private func makeSpace(
        in browser: BrowserManager,
        name: String,
        profileID: UUID? = UUID()
    ) throws -> Space {
        try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: name,
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profileID
            )
        )
    }

    private func makeStoreRestore(
        for browser: BrowserManager
    ) -> TabStoreRestoreService {
        TabStoreRestoreService(
            runtimeConnection: browser.runtimePortConnection,
            structuralLookup: browser.structuralLookupCoordinator,
            loadLifecycle: browser.startupRestoreLifecycle,
            executor: TabStoreRestoreAttemptExecutor(
                payloadLoader: TabRestoreLoader(
                    container: browser.modelContext.container
                ),
                structuralStore: TabStructuralSnapshotStore(
                    writes: TabStoreWriteExecutor(
                        container: browser.modelContext.container
                    )
                ),
                structuralLookup: browser.structuralLookupCoordinator,
                loadLifecycle: browser.startupRestoreLifecycle,
                payloadApplier: TabRestorePayloadApplyService(
                    tabFactory: browser.tabFactory,
                    structuralInstaller: browser.structuralInstallOwner,
                    runtimePreparation: TabRuntimePreparationOwner(
                        runtimeConnection: browser.runtimePortConnection
                    ),
                    lazyRestore: browser.lazyRestoreCoordinator,
                    persistence: browser.structuralPersistence
                )
            )
        )
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
        after persistence: TabStructuralPersistenceService,
        matching predicate: (TabsStateEntity) throws -> Bool
    ) async throws {
        let structuralPersist = persistence.scheduledPersistTask
        let selectionPersist = persistence.selectionPersistTask
        await structuralPersist?.value
        await selectionPersist?.value

        let context = ModelContext(container)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<TabsStateEntity>()).first)
        XCTAssertTrue(try predicate(state))
    }

    private func waitForStore(
        in container: ModelContainer,
        after persistence: TabStructuralPersistenceService,
        file: StaticString = #filePath,
        line: UInt = #line,
        matching predicate: (ModelContext) throws -> Bool
    ) async throws {
        let structuralPersist = persistence.scheduledPersistTask
        let selectionPersist = persistence.selectionPersistTask
        await structuralPersist?.value
        await selectionPersist?.value

        let context = ModelContext(container)
        XCTAssertTrue(try predicate(context), file: file, line: line)
    }

    private func awaitStructuralPersistence(
        _ persistence: TabStructuralPersistenceService
    ) async {
        await persistence.scheduledPersistTask?.value
    }
}
