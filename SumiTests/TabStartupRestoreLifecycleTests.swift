import Combine
import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class TabStartupRestoreLifecycleTests: XCTestCase {
    func testRestorePlannerSanitizesBlockedProfileReferences() throws {
        let blockedProfileID = UUID()
        let fallbackProfileID = UUID()
        let spaceID = UUID()
        let regularTabID = UUID()
        let launcherID = UUID()
        let payload = TabRestorePlanner().makePayload(
            from: TabRestoreStoreRecords(
                spaces: [
                    TabRestoreSpaceRecord(
                        id: spaceID,
                        name: "Blocked profile space",
                        icon: SumiPersistentGlyph.spaceDefaultIconValue,
                        index: 0,
                        workspaceThemeData: nil,
                        profileId: blockedProfileID
                    ),
                ],
                tabs: [
                    TabRestoreTabRecord(
                        id: regularTabID,
                        urlString: "https://example.com/regular",
                        name: "Regular",
                        isPinned: false,
                        isSpacePinned: false,
                        index: 0,
                        spaceId: spaceID,
                        profileId: blockedProfileID,
                        executionProfileId: blockedProfileID,
                        folderId: nil,
                        iconAsset: nil,
                        currentURLString: nil,
                        canGoBack: false,
                        canGoForward: false
                    ),
                    TabRestoreTabRecord(
                        id: launcherID,
                        urlString: "https://example.com/launcher",
                        name: "Launcher",
                        isPinned: true,
                        isSpacePinned: false,
                        index: 0,
                        spaceId: nil,
                        profileId: blockedProfileID,
                        executionProfileId: blockedProfileID,
                        folderId: nil,
                        iconAsset: nil,
                        currentURLString: nil,
                        canGoBack: false,
                        canGoForward: false
                    ),
                ],
                folders: [],
                states: []
            ),
            defaultProfileId: fallbackProfileID,
            blockedProfileIDs: [blockedProfileID]
        )

        XCTAssertEqual(payload.spaces.first?.profileId, fallbackProfileID)
        XCTAssertNil(payload.regularTabsBySpace[spaceID]?.first?.profileId)
        let launcher = try XCTUnwrap(
            payload.pinnedShortcutsByProfile[fallbackProfileID]?.first
        )
        XCTAssertEqual(launcher.id, launcherID)
        XCTAssertNil(launcher.executionProfileId)
        XCTAssertTrue(
            payload.repairReasons.contains("reassigned blocked space profile")
        )
        XCTAssertTrue(
            payload.repairReasons.contains("reassigned blocked launcher profile")
        )
    }

    func testRestoreStopsBeforePreparingReplacementAttachmentAfterInstallReentry() async throws {
        let payloadLoader = SuspendedFixedTabRestorePayloadLoader(
            payload: makeTwoTabRestorePayload()
        )
        let connection = TabRuntimePortConnection()
        let harness = try makeRestoreABAHarness(
            payloadLoader: payloadLoader,
            connection: connection
        )
        let liveSpace = Space(
            name: "Live Before Restore",
            profileId: UUID()
        )
        let liveTab = harness.manager.tabFactory.makeTab(
            url: URL(string: "https://example.com/live-before-restore")!,
            spaceId: liveSpace.id
        )
        harness.structuralLookup.withTransaction {
            harness.spaces.replaceSpaces([liveSpace])
            harness.spaces.replaceCurrentSpace(liveSpace)
            harness.regularTabs.replaceTabsBySpace([
                liveSpace.id: [liveTab],
            ])
            harness.membership.attach(liveTab)
            harness.selection.replaceCurrentTab(liveTab)
            harness.structuralLookup.requestPublish(scope: .all)
        }
        let starter = TabRuntimeAttachmentRestoreStarter(
            connection: connection,
            policy: TabStartupRestorePolicy(
                isEnabled: true,
                automaticallyStarts: false,
                requestedStructuralRevision:
                    harness.structuralLookup.mutationRevision
            ),
            lifecycle: harness.manager.startupRestoreLifecycle,
            restore: harness.restore
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
            starter.prepareForDetach()
            connection.detach()
            connection.attach(replacement)
        }

        starter.startManually(using: staleLease)
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
        XCTAssertEqual(harness.spaces.spaces.map(\.id), [liveSpace.id])
        XCTAssertEqual(
            harness.regularTabs
                .tabsBySpaceSnapshot()[liveSpace.id]?.map(\.id),
            [liveTab.id]
        )
        XCTAssertIdentical(harness.spaces.currentSpace, liveSpace)
        XCTAssertIdentical(harness.selection.currentTab, liveTab)
    }

    func testInstallAdmissionRejectsSynchronousStructuralRevisionChange() async throws {
        let payloadLoader = SuspendedFixedTabRestorePayloadLoader(
            payload: makeZeroTabRestorePayload()
        )
        let connection = TabRuntimePortConnection()
        let harness = try makeRestoreABAHarness(
            payloadLoader: payloadLoader,
            connection: connection
        )
        connection.attach(TestRuntimePorts.inactive)
        var liveSpace: Space?
        var didMutateStructure = false
        let observation = harness.manager.objectWillChange.sink {
            guard !didMutateStructure else { return }
            didMutateStructure = true
            let created = Space(
                name: "Live During Restore Admission",
                profileId: UUID()
            )
            harness.structuralLookup.withTransaction {
                harness.spaces.replaceSpaces([created])
                harness.spaces.replaceCurrentSpace(created)
                harness.structuralLookup.requestPublish(scope: .all)
            }
            liveSpace = created
        }

        harness.starter.startManually(using: connection.captureLease())
        await payloadLoader.started.wait()
        await payloadLoader.release.publish()
        await harness.restore.startupRestoreTask?.value
        observation.cancel()

        let admittedLiveSpace = try XCTUnwrap(liveSpace)
        XCTAssertEqual(
            harness.spaces.spaces.map(\.id),
            [admittedLiveSpace.id]
        )
        XCTAssertTrue(harness.manager.startupRestoreLifecycle.hasLoadedInitialData)
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
        let readinessObservation = harness.manager.tabStructureEventBus
            .initialDataLoadedPublisher
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
                membership: harness.membership,
                runtimePreparation: TabRuntimePreparationOwner(
                    runtimeConnection: connection
                ),
                selection: harness.selection
            ).run(using: replacementLease)
            if let currentSpace = harness.spaces.currentSpace {
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
        XCTAssertTrue(harness.manager.startupRestoreLifecycle.hasLoadedInitialData)
        XCTAssertEqual(readinessCount, 1)
        readinessObservation.cancel()
        harness.manager.structuralPersistence.cancelPendingPersistence()
    }

    func testReplacementAttachmentOwnsDeferredRestoreExactlyOnce() async throws {
        let payloadLoader = CountingTabRestorePayloadLoader(
            container: try makeInMemoryStartupDatabase()
        )
        let connection = TabRuntimePortConnection()
        let harness = try makeRestoreABAHarness(
            payloadLoader: payloadLoader,
            connection: connection,
            startupPolicy: TabStartupRestorePolicy(
                isEnabled: true,
                automaticallyStarts: true,
                requestedStructuralRevision: 0
            )
        )
        connection.attach(TestRuntimePorts.inactive)
        let staleLease = connection.captureLease()

        harness.starter.startAutomatically(using: staleLease)
        harness.starter.prepareForDetach()
        connection.detach()
        connection.attach(TestRuntimePorts.inactive)
        let replacementLease = connection.captureLease()
        harness.starter.startAutomatically(using: replacementLease)

        await payloadLoader.loaded.wait()
        await harness.restore.startupRestoreTask?.value
        let loadCount = await payloadLoader.loadCount()

        XCTAssertFalse(connection.accepts(staleLease))
        XCTAssertTrue(connection.accepts(replacementLease))
        XCTAssertEqual(loadCount, 1)
        XCTAssertTrue(harness.manager.startupRestoreLifecycle.didStartPersistedStateLoad)
        XCTAssertTrue(harness.manager.startupRestoreLifecycle.hasLoadedInitialData)
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
        let readinessObservation = harness.manager.tabStructureEventBus
            .initialDataLoadedPublisher
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

        XCTAssertFalse(harness.manager.startupRestoreLifecycle.hasLoadedInitialData)
        XCTAssertEqual(readinessCount, 0)
        XCTAssertNotNil(harness.restore.startupRestoreTask)
        let countAfterStaleCompletion = await payloadLoader.loadCount()
        XCTAssertEqual(countAfterStaleCompletion, 2)

        await payloadLoader.releaseSecond.publish()
        await replacementTask.value

        XCTAssertTrue(harness.manager.startupRestoreLifecycle.hasLoadedInitialData)
        XCTAssertEqual(readinessCount, 1)
        XCTAssertNil(harness.restore.startupRestoreTask)
        let terminalLoadCount = await payloadLoader.loadCount()
        XCTAssertEqual(terminalLoadCount, 2)
        XCTAssertFalse(connection.accepts(staleLease))
        XCTAssertTrue(connection.accepts(replacementLease))
        readinessObservation.cancel()
    }

    func testDisabledPersistenceDoesNotCreateAttachmentRestoreStarter() throws {
        let container = try makeInMemoryStartupDatabase()
        let connection = TabRuntimePortConnection()
        let harness = try makeRestoreABAHarness(
            payloadLoader: CountingTabRestorePayloadLoader(
                container: container
            ),
            connection: connection,
            startupPolicy: TabStartupRestorePolicy(
                isEnabled: false,
                automaticallyStarts: false,
                requestedStructuralRevision: 0
            )
        )
        connection.attach(TestRuntimePorts.inactive)
        harness.starter.startManually(using: connection.captureLease())
        XCTAssertFalse(
            harness.manager.startupRestoreLifecycle.didStartPersistedStateLoad
        )
    }

    func testShellDeferredRestoreStaysLazyUntilManualStart() async throws {
        let container = try makeInMemoryStartupDatabase()
        let connection = TabRuntimePortConnection()
        let harness = try makeRestoreABAHarness(
            payloadLoader: CountingTabRestorePayloadLoader(
                container: container
            ),
            connection: connection,
            startupPolicy: TabStartupRestorePolicy(
                isEnabled: true,
                automaticallyStarts: false,
                requestedStructuralRevision: 0
            )
        )
        connection.attach(TestRuntimePorts.inactive)
        XCTAssertFalse(
            harness.manager.startupRestoreLifecycle.didStartPersistedStateLoad
        )

        let initialDataLoaded = expectation(description: "initial data loaded")
        let loadedObservation = harness.manager.tabStructureEventBus
            .initialDataLoadedPublisher
            .sink { initialDataLoaded.fulfill() }
        let lease = connection.captureLease()
        harness.starter.startManually(using: lease)
        harness.starter.startManually(using: lease)
        await fulfillment(of: [initialDataLoaded])
        loadedObservation.cancel()

        XCTAssertTrue(
            harness.manager.startupRestoreLifecycle.didStartPersistedStateLoad
        )
        XCTAssertTrue(
            harness.manager.startupRestoreLifecycle.hasLoadedInitialData
        )
    }

    func testManualRestoreDetachCancelsOnlyExactLoadAndPreservesStructuralWrite() async throws {
        let payloadLoader = SuspendedTabRestorePayloadLoader()
        let connection = TabRuntimePortConnection()
        let harness = try makeRestoreABAHarness(
            payloadLoader: payloadLoader,
            connection: connection,
            startupPolicy: TabStartupRestorePolicy(
                isEnabled: true,
                automaticallyStarts: false,
                requestedStructuralRevision: 0
            )
        )
        connection.attach(TestRuntimePorts.inactive)

        harness.starter.startManually(using: connection.captureLease())
        await payloadLoader.started.wait()
        harness.manager.structuralPersistence.scheduleStructuralPersistence()

        XCTAssertNotNil(harness.restore.startupRestoreTask)
        XCTAssertNotNil(harness.manager.structuralPersistence.scheduledPersistTask)

        harness.starter.prepareForDetach()
        connection.detach()
        await payloadLoader.cancelled.wait()

        XCTAssertNil(harness.restore.startupRestoreTask)
        XCTAssertNotNil(harness.manager.structuralPersistence.scheduledPersistTask)
        XCTAssertNil(connection.current)
        harness.manager.structuralPersistence.cancelPendingPersistence()
    }
}

@MainActor
private struct RestoreABAHarness {
    let manager: TabManager
    let spaces: TabSpaceCollectionStateOwner
    let regularTabs: RegularTabCollectionStateOwner
    let selection: TabSelectionStateOwner
    let membership: TabCollectionMembershipOwner
    let structuralLookup: TabStructuralLookupCoordinator
    let restore: TabStoreRestoreService
    let starter: TabRuntimeAttachmentRestoreStarter
}

@MainActor
private func makeRestoreABAHarness(
    payloadLoader: any TabRestorePayloadLoading,
    connection: TabRuntimePortConnection,
    faviconService: any BrowserFaviconServicing = RestoreABAFaviconService(),
    startupPolicy: TabStartupRestorePolicy = TabStartupRestorePolicy(
        isEnabled: true,
        automaticallyStarts: false,
        requestedStructuralRevision: 0
    )
) throws -> RestoreABAHarness {
    let container = try makeInMemoryStartupDatabase()
    let eventBus = TabStructureEventBus()
    let manager = TabManager(
        database: container,
        webViewSessions: WebViewSessionRepository(),
        profileReferenceAdmission: try ProfileReferenceAdmissionLedger(
            database: container
        ),
        loadPersistedState: false,
        tabStructureEventBus: eventBus,
        faviconService: faviconService
    )
    let runtimePreparation = TabRuntimePreparationOwner(
        runtimeConnection: connection
    )
    let structuralLookup = TabStructuralLookupCoordinator(
        eventBus: eventBus,
        stateStore: manager.stateStore
    )
    let membership = TabCollectionMembershipOwner(
        structuralLookupOwner: structuralLookup.lookupOwner,
        state: manager.stateStore,
        runtimePreparation: runtimePreparation,
        runtimeConnection: connection
    )
    let lazyRestore = TabLazyRestoreCoordinator(
        spaces: manager.stateStore.spaces,
        regularTabs: manager.stateStore.regularTabs,
        membership: membership
    )
    let structuralInstall = TabStructuralInstallOwner(
        state: manager.stateStore,
        structuralLookup: structuralLookup,
        persistence: manager.structuralPersistence,
        publication: TabStructuralInstallPublication(
            changes: manager.objectWillChange,
            faviconService: manager.faviconService
        ),
        profileReferenceAdmission: manager.profileReferenceAdmission
    )
    let lifecycle = manager.startupRestoreLifecycle
    let executor = TabStoreRestoreAttemptExecutor(
        payloadLoader: payloadLoader,
        structuralStore: manager.structuralSnapshotStore,
        structuralLookup: structuralLookup,
        loadLifecycle: lifecycle,
        payloadApplier: TabRestorePayloadApplyService(
            tabFactory: manager.tabFactory,
            structuralInstaller: structuralInstall,
            runtimePreparation: runtimePreparation,
            lazyRestore: lazyRestore,
            persistence: manager.structuralPersistence
        )
    )
    let restore = TabStoreRestoreService(
        runtimeConnection: connection,
        structuralLookup: structuralLookup,
        loadLifecycle: lifecycle,
        executor: executor
    )
    return RestoreABAHarness(
        manager: manager,
        spaces: manager.stateStore.spaces,
        regularTabs: manager.stateStore.regularTabs,
        selection: manager.stateStore.selection,
        membership: membership,
        structuralLookup: structuralLookup,
        restore: restore,
        starter: TabRuntimeAttachmentRestoreStarter(
            connection: connection,
            policy: startupPolicy,
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

    init(container: SumiDatabase) {
        loader = TabRestoreLoader(database: container)
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
