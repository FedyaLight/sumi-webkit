import Combine
import SumiWebRuntime
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class TabStartupRestoreLifecycleTests: XCTestCase {
    func testRestoreStopsBeforePreparingReplacementAttachmentAfterInstallReentry() async throws {
        let payloadLoader = SuspendedFixedTabRestorePayloadLoader(
            payload: makeTwoTabRestorePayload()
        )
        let connection = TabRuntimePortConnection()
        let harness = try makeRestoreABAHarness(
            payloadLoader: payloadLoader,
            connection: connection
        )
        let liveSpace = harness.manager.spaceServices.catalog.createSpace(
            name: "Live Before Restore",
            profileId: UUID()
        )
        let liveTab = harness.manager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/live-before-restore",
            in: liveSpace,
            activate: true
        )
        var firstPreparationCount = 0
        var replacementPreparationCount = 0
        let replacement = TestRuntimePorts.make(
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in replacementPreparationCount += 1 }
            )
        )
        connection.attach(TestRuntimePorts.make(
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in firstPreparationCount += 1 }
            )
        ))
        let staleLease = connection.captureLease()
        var didReplaceAttachment = false
        let installObservation = harness.manager.objectWillChange.sink {
            guard didReplaceAttachment == false else { return }
            didReplaceAttachment = true
            harness.starter.prepareForDetach()
            connection.detach()
            connection.attach(replacement)
        }

        harness.starter.startManually(using: staleLease)
        await payloadLoader.started.wait()
        await payloadLoader.release.publish()
        await harness.restore.startupRestoreTask?.value
        installObservation.cancel()
        let replacementLease = connection.captureLease()

        XCTAssertTrue(didReplaceAttachment)
        XCTAssertFalse(connection.accepts(staleLease))
        XCTAssertTrue(connection.accepts(replacementLease))
        XCTAssertEqual(firstPreparationCount, 0)
        XCTAssertEqual(replacementPreparationCount, 0)
        XCTAssertEqual(harness.manager.spaceStateOwner.spaces.map(\.id), [liveSpace.id])
        XCTAssertEqual(
            harness.manager.regularTabCollectionStateOwner
                .tabsBySpaceSnapshot()[liveSpace.id]?.map(\.id),
            [liveTab.id]
        )
        XCTAssertIdentical(harness.manager.spaceStateOwner.currentSpace, liveSpace)
        XCTAssertIdentical(harness.manager.selectionStateOwner.currentTab, liveTab)
    }

    func testInstallAdmissionRejectsSynchronousStructuralRevisionChange() async throws {
        let payloadLoader = SuspendedFixedTabRestorePayloadLoader(
            payload: makeZeroTabRestorePayload()
        )
        let connection = TabRuntimePortConnection()
        var structuralRevision: UInt64 = 0
        let harness = try makeRestoreABAHarness(
            payloadLoader: payloadLoader,
            connection: connection,
            structuralRevision: { structuralRevision }
        )
        connection.attach(TestRuntimePorts.inactive)
        var liveSpace: Space?
        var didMutateStructure = false
        let observation = harness.manager.objectWillChange.sink {
            guard !didMutateStructure else { return }
            didMutateStructure = true
            structuralRevision = 1
            liveSpace = harness.manager.spaceServices.catalog.createSpace(
                name: "Live During Restore Admission",
                profileId: UUID()
            )
        }

        harness.starter.startManually(using: connection.captureLease())
        await payloadLoader.started.wait()
        await payloadLoader.release.publish()
        await harness.restore.startupRestoreTask?.value
        observation.cancel()

        let admittedLiveSpace = try XCTUnwrap(liveSpace)
        XCTAssertEqual(
            harness.manager.spaceStateOwner.spaces.map(\.id),
            [admittedLiveSpace.id]
        )
        XCTAssertTrue(harness.lifecycle.hasLoadedInitialData)
        let loadCount = await payloadLoader.loadCount()
        XCTAssertEqual(loadCount, 1)
    }

    func testRestoreStopsAfterPreparationSupersedesExactAttachment() async throws {
        let payloadLoader = SuspendedFixedTabRestorePayloadLoader(
            payload: makeTwoTabRestorePayload()
        )
        let connection = TabRuntimePortConnection()
        let harness = try makeRestoreABAHarness(
            payloadLoader: payloadLoader,
            connection: connection
        )
        var firstPreparationCount = 0
        var replacementPreparationCount = 0
        var replacementThemeSyncCount = 0
        let replacement = TestRuntimePorts.make(
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in replacementPreparationCount += 1 }
            ),
            syncWorkspaceThemeAcrossWindows: { _, _ in
                replacementThemeSyncCount += 1
            }
        )
        connection.attach(TestRuntimePorts.make(
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in
                    firstPreparationCount += 1
                    harness.starter.prepareForDetach()
                    connection.detach()
                    connection.attach(replacement)
                }
            )
        ))
        let staleLease = connection.captureLease()

        harness.starter.startManually(using: staleLease)
        await payloadLoader.started.wait()
        await payloadLoader.release.publish()
        await harness.restore.startupRestoreTask?.value
        let replacementLease = connection.captureLease()

        XCTAssertFalse(connection.accepts(staleLease))
        XCTAssertTrue(connection.accepts(replacementLease))
        XCTAssertEqual(firstPreparationCount, 1)
        XCTAssertEqual(replacementPreparationCount, 0)
        XCTAssertEqual(replacementThemeSyncCount, 0)
    }

    func testZeroTabRestoreStopsAfterLateInstallPublicationSupersedesAttachment() async throws {
        let payloadLoader = SuspendedFixedTabRestorePayloadLoader(
            payload: makeZeroTabRestorePayload()
        )
        let connection = TabRuntimePortConnection()
        let faviconService = RestoreABAFaviconService()
        let harness = try makeRestoreABAHarness(
            payloadLoader: payloadLoader,
            connection: connection,
            faviconService: faviconService
        )
        var readinessCount = 0
        let readinessObservation = harness.eventBus.initialDataLoadedPublisher
            .sink { readinessCount += 1 }
        var replacementThemeSyncCount = 0
        let replacement = TestRuntimePorts.make(
            syncWorkspaceThemeAcrossWindows: { _, _ in
                replacementThemeSyncCount += 1
            }
        )
        connection.attach(TestRuntimePorts.inactive)
        let staleLease = connection.captureLease()
        faviconService.onSyncShortcutPins = {
            harness.starter.prepareForDetach()
            connection.detach()
            connection.attach(replacement)
            let replacementLease = connection.captureLease()
            _ = TabRuntimeAttachmentBootstrap(
                connection: connection,
                membership: harness.manager.tabCollectionMembershipOwner,
                runtimePreparation: TabRuntimePreparationOwner(
                    runtimeConnection: connection
                ),
                selection: harness.manager.selectionStateOwner
            ).run(using: replacementLease)
            if let currentSpace = harness.manager.spaceStateOwner.currentSpace {
                replacement.syncWorkspaceThemeAcrossWindows(
                    for: currentSpace,
                    animate: false
                )
            }
            harness.starter.startManually(using: replacementLease)
            harness.manager.structuralPersistence
                .scheduleStructuralPersistence()
        }

        harness.starter.startManually(using: staleLease)
        await payloadLoader.started.wait()
        harness.manager.structuralPersistence.scheduleStructuralPersistence()
        let schedulingRevision = harness.manager.structuralPersistence
            .schedulingRevision
        await payloadLoader.release.publish()
        await harness.restore.startupRestoreTask?.value
        let replacementLease = connection.captureLease()

        XCTAssertEqual(faviconService.syncCount, 1)
        XCTAssertFalse(connection.accepts(staleLease))
        XCTAssertTrue(connection.accepts(replacementLease))
        XCTAssertEqual(replacementThemeSyncCount, 1)
        XCTAssertGreaterThan(
            harness.manager.structuralPersistence.schedulingRevision,
            schedulingRevision
        )
        XCTAssertNotNil(
            harness.manager.structuralPersistence.scheduledPersistTask
        )
        let loadCount = await payloadLoader.loadCount()
        XCTAssertEqual(loadCount, 1)
        XCTAssertTrue(harness.lifecycle.hasLoadedInitialData)
        XCTAssertEqual(readinessCount, 1)
        readinessObservation.cancel()
        harness.manager.structuralPersistence.cancelPendingPersistence()
    }

    func testReplacementAttachmentOwnsDeferredRestoreExactlyOnce() async throws {
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        let lifecycle = TabStartupRestoreLifecycle(eventBus: TabStructureEventBus())
        let payloadLoader = CountingTabRestorePayloadLoader(container: container)
        let connection = TabRuntimePortConnection()
        let restore = TabStoreRestoreService(
            payloadLoader: payloadLoader,
            structuralStore: tabManager.structuralSnapshotStore,
            runtimeConnection: connection,
            structuralRevision: { 0 },
            loadLifecycle: lifecycle,
            payloadApplier: TabRestorePayloadApplyService(
                tabFactory: tabManager.tabFactory,
                structuralInstaller: tabManager.structuralInstallOwner,
                runtimePreparation: tabManager.runtimePreparationOwner,
                lazyRestore: tabManager.lazyRestoreCoordinator,
                persistence: tabManager.structuralPersistence
            )
        )
        let starter = TabRuntimeAttachmentRestoreStarter(
            connection: connection,
            policy: TabStartupRestorePolicy(
                isEnabled: true,
                automaticallyStarts: true,
                requestedStructuralRevision: 0
            ),
            lifecycle: lifecycle,
            restore: restore
        )
        connection.attach(TestRuntimePorts.inactive)
        let staleLease = connection.captureLease()

        starter.startAutomatically(using: staleLease)
        starter.prepareForDetach()
        connection.detach()
        connection.attach(TestRuntimePorts.inactive)
        let replacementLease = connection.captureLease()
        starter.startAutomatically(using: replacementLease)

        await payloadLoader.loaded.wait()
        await restore.startupRestoreTask?.value
        let loadCount = await payloadLoader.loadCount()

        XCTAssertFalse(connection.accepts(staleLease))
        XCTAssertTrue(connection.accepts(replacementLease))
        XCTAssertEqual(loadCount, 1)
        XCTAssertTrue(lifecycle.didStartPersistedStateLoad)
        XCTAssertTrue(lifecycle.hasLoadedInitialData)
    }

    func testStaleNoncooperativeLoadCannotClearOrFinishReplacementLoad() async throws {
        let payloadLoader = SequencedSuspendedRestorePayloadLoader(
            payload: makeZeroTabRestorePayload()
        )
        let connection = TabRuntimePortConnection()
        let harness = try makeRestoreABAHarness(
            payloadLoader: payloadLoader,
            connection: connection
        )
        var readinessCount = 0
        let readinessObservation = harness.eventBus.initialDataLoadedPublisher
            .sink { readinessCount += 1 }
        connection.attach(TestRuntimePorts.inactive)
        let staleLease = connection.captureLease()

        harness.starter.startManually(using: staleLease)
        await payloadLoader.firstStarted.wait()
        let staleTask = try XCTUnwrap(harness.restore.startupRestoreTask)
        harness.starter.prepareForDetach()
        connection.detach()
        connection.attach(TestRuntimePorts.inactive)
        let replacementLease = connection.captureLease()
        harness.starter.startManually(using: replacementLease)
        await payloadLoader.secondStarted.wait()
        let replacementTask = try XCTUnwrap(harness.restore.startupRestoreTask)

        await payloadLoader.releaseFirst.publish()
        await payloadLoader.firstReturned.wait()
        await staleTask.value

        XCTAssertFalse(harness.lifecycle.hasLoadedInitialData)
        XCTAssertEqual(readinessCount, 0)
        XCTAssertNotNil(harness.restore.startupRestoreTask)
        let countAfterStaleCompletion = await payloadLoader.loadCount()
        XCTAssertEqual(countAfterStaleCompletion, 2)

        await payloadLoader.releaseSecond.publish()
        await replacementTask.value

        XCTAssertTrue(harness.lifecycle.hasLoadedInitialData)
        XCTAssertEqual(readinessCount, 1)
        XCTAssertNil(harness.restore.startupRestoreTask)
        let terminalLoadCount = await payloadLoader.loadCount()
        XCTAssertEqual(terminalLoadCount, 2)
        XCTAssertFalse(connection.accepts(staleLease))
        XCTAssertTrue(connection.accepts(replacementLease))
        readinessObservation.cancel()
    }

    func testDisabledPersistenceDoesNotCreateAttachmentRestoreStarter() throws {
        let tabManager = try makeInMemoryTabManager(
            loadPersistedState: false,
            attachRuntimePorts: false
        )

        XCTAssertNil(tabManager.lifecycleOwners.runtimeAttachmentRestoreStarter)
        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(
                TestRuntimePorts.inactive
            ),
            .attached
        )
        XCTAssertNil(tabManager.lifecycleOwners.runtimeAttachmentRestoreStarter)
        XCTAssertFalse(
            tabManager.startupRestoreLifecycle.didStartPersistedStateLoad
        )
    }

    func testShellDeferredRestoreStaysLazyUntilManualStart() async throws {
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: true,
            automaticallyStartPersistedStateLoad: false
        )

        XCTAssertNotNil(tabManager.lifecycleOwners.runtimeAttachmentRestoreStarter)
        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(
                TestRuntimePorts.inactive
            ),
            .attached
        )
        XCTAssertNotNil(tabManager.lifecycleOwners.runtimeAttachmentRestoreStarter)
        XCTAssertFalse(
            tabManager.startupRestoreLifecycle.didStartPersistedStateLoad
        )

        let initialDataLoaded = expectation(description: "initial data loaded")
        let loadedObservation = tabManager.tabStructureEventBus
            .initialDataLoadedPublisher
            .sink { initialDataLoaded.fulfill() }
        tabManager.runtimePortsAttachmentOwner
            .startPersistedStateRestoreIfNeeded()
        tabManager.runtimePortsAttachmentOwner
            .startPersistedStateRestoreIfNeeded()
        await fulfillment(of: [initialDataLoaded])
        loadedObservation.cancel()

        XCTAssertTrue(
            tabManager.startupRestoreLifecycle.didStartPersistedStateLoad
        )
        XCTAssertTrue(tabManager.startupRestoreLifecycle.hasLoadedInitialData)
    }

    func testManualRestoreDetachCancelsOnlyExactLoadAndPreservesStructuralWrite() async throws {
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        let lifecycle = TabStartupRestoreLifecycle(eventBus: TabStructureEventBus())
        let payloadLoader = SuspendedTabRestorePayloadLoader()
        let connection = TabRuntimePortConnection()
        let restore = TabStoreRestoreService(
            payloadLoader: payloadLoader,
            structuralStore: tabManager.structuralSnapshotStore,
            runtimeConnection: connection,
            structuralRevision: { 0 },
            loadLifecycle: lifecycle,
            payloadApplier: TabRestorePayloadApplyService(
                tabFactory: tabManager.tabFactory,
                structuralInstaller: tabManager.structuralInstallOwner,
                runtimePreparation: tabManager.runtimePreparationOwner,
                lazyRestore: tabManager.lazyRestoreCoordinator,
                persistence: tabManager.structuralPersistence
            )
        )
        let starter = TabRuntimeAttachmentRestoreStarter(
            connection: connection,
            policy: TabStartupRestorePolicy(
                isEnabled: true,
                automaticallyStarts: false,
                requestedStructuralRevision: 0
            ),
            lifecycle: lifecycle,
            restore: restore
        )
        connection.attach(TestRuntimePorts.inactive)

        starter.startManually(using: connection.captureLease())
        await payloadLoader.started.wait()
        tabManager.structuralPersistence.scheduleStructuralPersistence()

        XCTAssertNotNil(restore.startupRestoreTask)
        XCTAssertNotNil(tabManager.structuralPersistence.scheduledPersistTask)

        starter.prepareForDetach()
        connection.detach()
        await payloadLoader.cancelled.wait()

        XCTAssertNil(restore.startupRestoreTask)
        XCTAssertNotNil(tabManager.structuralPersistence.scheduledPersistTask)
        XCTAssertNil(connection.current)
        tabManager.structuralPersistence.cancelPendingPersistence()
    }
}

@MainActor
private struct RestoreABAHarness {
    let manager: TabManager
    let eventBus: TabStructureEventBus
    let lifecycle: TabStartupRestoreLifecycle
    let restore: TabStoreRestoreService
    let starter: TabRuntimeAttachmentRestoreStarter
}

@MainActor
private func makeRestoreABAHarness(
    payloadLoader: any TabRestorePayloadLoading,
    connection: TabRuntimePortConnection,
    faviconService: any BrowserFaviconServicing = RestoreABAFaviconService(),
    structuralRevision: @escaping @MainActor () -> UInt64 = { 0 }
) throws -> RestoreABAHarness {
    let container = try makeInMemoryStartupModelContainer()
    let manager = TabManager(
        context: container.mainContext,
        webViewSessions: WebViewSessionRepository(),
        loadPersistedState: false,
        faviconService: faviconService
    )
    let eventBus = TabStructureEventBus()
    let lifecycle = TabStartupRestoreLifecycle(eventBus: eventBus)
    let restore = TabStoreRestoreService(
        payloadLoader: payloadLoader,
        structuralStore: manager.structuralSnapshotStore,
        runtimeConnection: connection,
        structuralRevision: structuralRevision,
        loadLifecycle: lifecycle,
        payloadApplier: TabRestorePayloadApplyService(
            tabFactory: manager.tabFactory,
            structuralInstaller: manager.structuralInstallOwner,
            runtimePreparation: TabRuntimePreparationOwner(
                runtimeConnection: connection
            ),
            lazyRestore: manager.lazyRestoreCoordinator,
            persistence: manager.structuralPersistence
        )
    )
    return RestoreABAHarness(
        manager: manager,
        eventBus: eventBus,
        lifecycle: lifecycle,
        restore: restore,
        starter: TabRuntimeAttachmentRestoreStarter(
            connection: connection,
            policy: TabStartupRestorePolicy(
                isEnabled: true,
                automaticallyStarts: false,
                requestedStructuralRevision: 0
            ),
            lifecycle: lifecycle,
            restore: restore
        )
    )
}

private func makeZeroTabRestorePayload() -> TabRestorePayload {
    let spaceID = UUID()
    return TabRestorePlanner().makePayload(
        from: TabRestoreStoreRecords(
            spaces: [
                TabRestoreSpaceRecord(
                    id: spaceID,
                    name: "Restored Empty Space",
                    icon: SumiPersistentGlyph.spaceDefaultIconValue,
                    index: 0,
                    workspaceThemeData: nil,
                    profileId: nil
                ),
            ],
            tabs: [],
            folders: [],
            states: [
                TabRestoreStateRecord(
                    currentTabID: nil,
                    currentSpaceID: spaceID,
                    splitGroupsData: nil
                ),
            ]
        ),
        defaultProfileId: nil
    )
}

private func makeTwoTabRestorePayload() -> TabRestorePayload {
    let spaceID = UUID()
    let firstTabID = UUID()
    let secondTabID = UUID()
    return TabRestorePlanner().makePayload(
        from: TabRestoreStoreRecords(
            spaces: [
                TabRestoreSpaceRecord(
                    id: spaceID,
                    name: "Restored",
                    icon: SumiPersistentGlyph.spaceDefaultIconValue,
                    index: 0,
                    workspaceThemeData: nil,
                    profileId: nil
                ),
            ],
            tabs: [
                TabRestoreTabRecord(
                    id: firstTabID,
                    urlString: "https://example.com/first",
                    name: "First",
                    isPinned: false,
                    isSpacePinned: false,
                    index: 0,
                    spaceId: spaceID,
                    profileId: nil,
                    executionProfileId: nil,
                    folderId: nil,
                    iconAsset: nil,
                    currentURLString: nil,
                    canGoBack: false,
                    canGoForward: false
                ),
                TabRestoreTabRecord(
                    id: secondTabID,
                    urlString: "https://example.com/second",
                    name: "Second",
                    isPinned: false,
                    isSpacePinned: false,
                    index: 1,
                    spaceId: spaceID,
                    profileId: nil,
                    executionProfileId: nil,
                    folderId: nil,
                    iconAsset: nil,
                    currentURLString: nil,
                    canGoBack: false,
                    canGoForward: false
                ),
            ],
            folders: [],
            states: [
                TabRestoreStateRecord(
                    currentTabID: firstTabID,
                    currentSpaceID: spaceID,
                    splitGroupsData: nil
                ),
            ]
        ),
        defaultProfileId: nil
    )
}

private actor SuspendedFixedTabRestorePayloadLoader: TabRestorePayloadLoading {
    let started = AsyncTestReceipt()
    let release = AsyncTestReceipt()
    private let payload: TabRestorePayload
    private var count = 0

    init(payload: TabRestorePayload) {
        self.payload = payload
    }

    func load(defaultProfileId _: UUID?) async throws -> TabRestorePayload {
        count += 1
        await started.publish()
        await release.wait()
        return payload
    }

    func loadCount() -> Int { count }
}

private actor SequencedSuspendedRestorePayloadLoader: TabRestorePayloadLoading {
    let firstStarted = AsyncTestReceipt()
    let secondStarted = AsyncTestReceipt()
    let releaseFirst = AsyncTestReceipt()
    let releaseSecond = AsyncTestReceipt()
    let firstReturned = AsyncTestReceipt()
    private let payload: TabRestorePayload
    private var count = 0

    init(payload: TabRestorePayload) {
        self.payload = payload
    }

    func load(defaultProfileId _: UUID?) async throws -> TabRestorePayload {
        count += 1
        if count == 1 {
            await firstStarted.publish()
            await releaseFirst.wait()
            await firstReturned.publish()
        } else {
            await secondStarted.publish()
            await releaseSecond.wait()
        }
        return payload
    }

    func loadCount() -> Int { count }
}

@MainActor
private final class RestoreABAFaviconService: BrowserFaviconServicing {
    var onSyncShortcutPins: () -> Void = {}
    private(set) var syncCount = 0

    func partition(profile: Profile?) -> SumiFaviconPartition {
        .regular(profile?.id)
    }

    func invalidateSite(domain _: String, profile _: Profile?) {}

    func syncShortcutPins(_: [ShortcutPin]) {
        syncCount += 1
        onSyncShortcutPins()
    }

    func syncBookmarks(
        _: [SumiBookmark],
        partition _: SumiFaviconPartition
    ) {}

    func clearFaviconPartition(for _: Profile) {}

#if DEBUG
    func drainRuntimeTasksForTests(cancel _: Bool) async {}
#endif
}

private actor CountingTabRestorePayloadLoader: TabRestorePayloadLoading {
    private let loader: TabRestoreLoader
    private var count = 0
    let loaded = AsyncTestReceipt()

    init(container: ModelContainer) {
        loader = TabRestoreLoader(container: container)
    }

    func load(defaultProfileId: UUID?) async throws -> TabRestorePayload {
        count += 1
        let payload = try await loader.load(defaultProfileId: defaultProfileId)
        await loaded.publish()
        return payload
    }

    func loadCount() -> Int { count }
}

private actor SuspendedTabRestorePayloadLoader: TabRestorePayloadLoading {
    let started = AsyncTestReceipt()
    let cancelled = AsyncTestReceipt()
    let release = AsyncTestReceipt()

    func load(defaultProfileId _: UUID?) async throws -> TabRestorePayload {
        await started.publish()
        await withTaskCancellationHandler {
            await release.wait()
        } onCancel: {
            Task { await self.release.publish() }
        }
        await cancelled.publish()
        try Task.checkCancellation()
        throw CancellationError()
    }
}

private actor AsyncTestReceipt {
    private var wasPublished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard wasPublished == false else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func publish() {
        guard wasPublished == false else { return }
        wasPublished = true
        let waiters = waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
