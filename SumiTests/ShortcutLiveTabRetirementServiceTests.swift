import Combine
import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ShortcutLiveTabRetirementServiceTests: XCTestCase {
    func testRetirementProjectionReportsSelectionChangeFromFinalOverride() {
        let windowID = UUID()
        let spaceID = UUID()
        let selectedTabID = UUID()
        let selectedPinID = UUID()
        let retiredPinID = UUID()
        let retiredTab = Tab(
            url: URL(string: "https://background.example")!,
            name: "Background",
            spaceId: spaceID,
            loadsCachedFaviconOnInit: false
        )
        let entry = LiveShortcutTabEntry(
            windowId: windowID,
            pinId: retiredPinID,
            tab: retiredTab,
            presentationPage: LiveShortcutPresentationPageReceipt(
                windowID: windowID,
                spaceID: spaceID,
                profileID: nil
            )
        )
        let source = BrowserWindowShortcutMutationState(
            currentTabId: selectedTabID,
            currentSpaceId: spaceID,
            currentShortcutPinId: selectedPinID
        )
        var override = source
        override.currentTabId = UUID()
        override.currentShortcutPinId = nil

        let update = ShortcutLiveRetirementWindowProjection
            .removingInstances(
                [entry],
                from: source,
                targetOverride: override
            )

        XCTAssertEqual(update.target, override)
        XCTAssertTrue(update.didClearCurrentSelection)
    }

    func testMissingRuntimeLeavesLiveRegistryUnchanged() throws {
        let container = try makeInMemoryStartupDatabase()
        let webViewSessions = WebViewSessionRepository()
        let tabManager = TabManager(
            database: container,
            webViewSessions: webViewSessions,
            profileReferenceAdmission: try ProfileReferenceAdmissionLedger(
                database: container
            ),
            loadPersistedState: false
        )
        let state = tabManager.stateStore
        let structuralLookup = TabStructuralLookupCoordinator(
            eventBus: tabManager.tabStructureEventBus,
            stateStore: state
        )
        let membership = TabCollectionMembershipOwner(
            structuralLookupOwner: structuralLookup.lookupOwner,
            state: state,
            runtimePreparation: TabRuntimePreparationOwner(
                runtimeConnection: tabManager.runtimePortConnection
            ),
            runtimeConnection: tabManager.runtimePortConnection
        )
        let registry = LiveShortcutTabRegistry(
            storage: state.transientTabs,
            structuralLookup: structuralLookup
        )
        let retirement = ShortcutLiveTabRetirementService(
            registry: registry,
            structuralLookup: structuralLookup,
            runtimeConnection: tabManager.runtimePortConnection,
            runtimeTeardown: TabRuntimeTeardownService(
                persistence: tabManager.structuralPersistence,
                membership: membership,
                webViewSessions: webViewSessions
            ),
            windowMutations: BrowserWindowShortcutMutationOwner(),
            splitGroups: state.splitGroups,
            splitMutations: SplitGroupMutationService(
                store: state.splitGroups,
                publication: TabStructuralMutationPublisher(
                    persistence: tabManager.structuralPersistence,
                    faviconService: tabManager.faviconService,
                    lookup: structuralLookup,
                    changes: tabManager.objectWillChange,
                    regularTabs: state.regularTabs
                )
            )
        )
        let space = Space(name: "Space")
        state.spaces.replaceSpaces([space])
        let pin = makePin(spaceId: space.id)
        let windowId = UUID()
        let liveTab = tabManager.tabFactory.makeTab(
            url: pin.launchURL,
            spaceId: space.id
        )
        liveTab.bindToShortcutPin(pin)
        membership.attach(liveTab)
        XCTAssertTrue(registry.register(
            liveTab,
            for: pin.id,
            in: windowId,
            presentationPage: LiveShortcutPresentationPageReceipt(
                windowID: windowId,
                spaceID: space.id,
                profileID: nil
            )
        ))

        let result = retirement.retire(pinId: pin.id, in: windowId)

        XCTAssertFalse(result.didRetire)
        XCTAssertIdentical(
            registry.tab(for: pin.id, in: windowId),
            liveTab
        )
        XCTAssertIdentical(membership.tab(for: liveTab.id), liveTab)
    }

    func testBlockedPhysicalCleanupLeavesShortcutStructurallyLive() throws {
        let windowState = BrowserWindowState()
        let probe = RetirementProbe()
        let tabManager = try makeFixture(
            windows: [windowState],
            probe: probe
        )
        let space = try makeSpace(in: tabManager)
        let pin = makePin(spaceId: space.id)
        let liveTab = tabManager.makeLiveTab(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )!
        var invalidatedNowPlayingTabIDs: [UUID] = []
        liveTab.mediaRuntime.callbacks = TabMediaRuntimeCallbacks(
            scheduleNowPlayingRefresh: { _ in /* No-op. */ },
            notifyNowPlayingTabUnloaded: { tabID in
                invalidatedNowPlayingTabIDs.append(tabID)
            }
        )
        liveTab.replaceUntrackedWebView(WKWebView())
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id

        let retirement = tabManager.retirement.retire(
            pinId: pin.id,
            in: windowState.id
        )

        XCTAssertFalse(retirement.didRetire)
        XCTAssertIdentical(
            tabManager.registry.tab(
                for: pin.id,
                in: windowState.id
            ),
            liveTab
        )
        XCTAssertIdentical(
            tabManager.membership.tab(for: liveTab.id),
            liveTab
        )
        XCTAssertEqual(windowState.currentTabId, liveTab.id)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertTrue(probe.tabClosureBatches.isEmpty)
        XCTAssertTrue(probe.extensionClosedTabIds.isEmpty)
        XCTAssertTrue(probe.unloadedTabIds.isEmpty)
        XCTAssertTrue(invalidatedNowPlayingTabIDs.isEmpty)
    }

    func testGenericTabRemovalDelegatesLiveShortcutToCanonicalRetirementOnce() throws {
        let windowState = BrowserWindowState()
        let probe = RetirementProbe()
        let tabManager = try makeFixture(windows: [windowState], probe: probe)
        let space = try makeSpace(in: tabManager)
        let pin = makePin(spaceId: space.id)
        let liveTab = tabManager.makeLiveTab(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )!

        _ = tabManager.retirement.retire(tabId: liveTab.id)

        XCTAssertNil(tabManager.registry.entry(tabId: liveTab.id))
        XCTAssertTrue(probe.tabClosureBatches.isEmpty)
        XCTAssertTrue(probe.unloadedTabIds.isEmpty)
        XCTAssertEqual(probe.extensionClosedTabIds, [liveTab.id])
    }

    func testGenericRemovalValidatesClearedSelectedShortcut() throws {
        let windowState = BrowserWindowState()
        let probe = RetirementProbe()
        let tabManager = try makeFixture(
            windows: [windowState],
            probe: probe
        )
        let space = try makeSpace(in: tabManager)
        let pin = makePin(spaceId: space.id)
        let liveTab = tabManager.makeLiveTab(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )!
        windowState.currentSpaceId = space.id
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role

        _ = tabManager.retirement.retire(tabId: liveTab.id)

        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertEqual(probe.validationCount, 1)
    }

    func testValidationAttachmentReplacementSuppressesStalePersistence() throws {
        let windowState = BrowserWindowState()
        let probe = RetirementProbe()
        var runtimeAttachment: TabRuntimePortConnection!
        let tabManager = try makeFixture(
            windows: [windowState],
            probe: probe,
            receiveRuntimeAttachment: { runtimeAttachment = $0 }
        )
        let space = try makeSpace(in: tabManager)
        let pin = makePin(spaceId: space.id)
        let liveTab = tabManager.makeLiveTab(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )!
        windowState.currentSpaceId = space.id
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role
        var replacementPersistenceCount = 0
        probe.validationAction = { [weak tabManager] in
            guard tabManager != nil else {
                XCTFail("Retirement fixture deallocated during validation")
                return
            }
            runtimeAttachment.detach()
            runtimeAttachment.attach(TestRuntimePorts.make(
                windowState: { id in
                    id == windowState.id ? windowState : nil
                },
                windows: { [(windowState.id, windowState)] },
                windowStates: { [windowState] },
                persistWindowSession: { _ in
                    replacementPersistenceCount += 1
                }
            ))
        }

        _ = tabManager.retirement.retire(tabId: liveTab.id)

        XCTAssertEqual(probe.validationCount, 1)
        XCTAssertTrue(probe.persistedWindowIds.isEmpty)
        XCTAssertEqual(replacementPersistenceCount, 0)
        XCTAssertNotNil(tabManager.runtimeConnection.current)
    }

    func testPreparedRuntimeLeaseSurvivesDetachFromStructuralSubscriber() throws {
        let windowState = BrowserWindowState()
        let probe = RetirementProbe()
        var runtimeAttachment: TabRuntimePortConnection!
        let tabManager = try makeFixture(
            windows: [windowState],
            probe: probe,
            receiveRuntimeAttachment: { runtimeAttachment = $0 }
        )
        let space = try makeSpace(in: tabManager)
        let pin = makePin(spaceId: space.id)
        XCTAssertNotNil(
            tabManager.makeLiveTab(
                pin,
                in: windowState.id,
                currentSpaceId: space.id
            )
        )
        let cancellable = tabManager.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { [weak tabManager] _ in
                if tabManager != nil {
                    runtimeAttachment.detach()
                }
            }

        let result = tabManager.retirement.retire(
            pinId: pin.id,
            in: windowState.id
        )

        XCTAssertTrue(result.didRetire)
        XCTAssertNil(tabManager.runtimeConnection.current)
        XCTAssertTrue(probe.unloadedTabIds.isEmpty)
        _ = cancellable
    }

    func testBackgroundLauncherRetirementInvalidatesMediaAndRunsCompleteTeardownOnce() throws {
        let windowState = BrowserWindowState()
        let probe = RetirementProbe()
        let runtimeRetirement = TestRuntimePorts.RetirementCapabilities(
            canRetire: { _ in true },
            beginCommitted: { _ in true },
            committedRetirementIsExact: { _ in true },
            destroy: { generations in
                probe.destroyedGenerationTabIDs.append(
                    generations.map(\.tabID)
                )
            },
            destroyAfterTerminalDrain: { _ in
                XCTFail("Committed retirement must use normal destruction")
            }
        )
        let tabManager = try makeFixture(
            windows: [windowState],
            probe: probe,
            retirement: runtimeRetirement
        )
        let space = try makeSpace(in: tabManager)
        let pin = makePin(spaceId: space.id)
        tabManager.structuralMutations
            .setSpacePinnedShortcuts([pin], for: space.id)
        let liveTab = tabManager.makeLiveTab(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )!
        var invalidatedNowPlayingTabIDs: [UUID] = []
        liveTab.mediaRuntime.callbacks = TabMediaRuntimeCallbacks(
            scheduleNowPlayingRefresh: { _ in /* No-op. */ },
            notifyNowPlayingTabUnloaded: { tabID in
                invalidatedNowPlayingTabIDs.append(tabID)
            }
        )
        liveTab.replaceUntrackedWebView(WKWebView())
        let unrelatedSelection = UUID()
        windowState.currentTabId = unrelatedSelection
        windowState.selectedShortcutPinForSpace[space.id] = pin.id
        windowState.selectionHistory.recentSelectionItemsBySpace[space.id] = [
            .shortcutPin(pin.id),
        ]
        let lifecycle = TabLifecycleNotificationRecorder(tab: liveTab)

        let retirement = tabManager.retirement.retire(
            pinId: pin.id,
            in: windowState.id
        )
        let repeatedRetirement = tabManager.retirement.retire(
            pinId: pin.id,
            in: windowState.id
        )

        XCTAssertTrue(retirement.didRetire)
        XCTAssertEqual(retirement.retiredTabIds, [liveTab.id])
        XCTAssertFalse(retirement.didClearCurrentSelection)
        XCTAssertTrue(retirement.windowStatesNeedingPersistence.isEmpty)
        XCTAssertFalse(repeatedRetirement.didRetire)
        XCTAssertEqual(windowState.currentTabId, unrelatedSelection)
        XCTAssertEqual(
            windowState.selectedShortcutPinForSpace[space.id],
            pin.id,
            "Plain unload keeps the launcher's remembered Space selection"
        )
        XCTAssertEqual(
            windowState.selectionHistory.recentSelectionItemsBySpace[space.id],
            [.shortcutPin(pin.id)]
        )
        XCTAssertNil(
            tabManager.registry.tab(
                for: pin.id,
                in: windowState.id
            )
        )
        XCTAssertNil(tabManager.membership.tab(for: liveTab.id))
        XCTAssertTrue(probe.tabClosureBatches.isEmpty)
        XCTAssertEqual(probe.extensionClosedTabIds, [liveTab.id])
        XCTAssertTrue(probe.unloadedTabIds.isEmpty)
        XCTAssertEqual(invalidatedNowPlayingTabIDs, [liveTab.id])
        XCTAssertEqual(probe.destroyedGenerationTabIDs, [[liveTab.id]])
        XCTAssertEqual(lifecycle.count, 1)
    }

    func testDeletedPinRetiresEveryWindowInstanceAndPersistsEachChangedWindowOnce() throws {
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        let proxyWindow = BrowserWindowState()
        let windows = [firstWindow, secondWindow, proxyWindow]
        let probe = RetirementProbe()
        let tabManager = try makeFixture(windows: windows, probe: probe)
        let space = try makeSpace(in: tabManager)
        let pin = makePin(spaceId: space.id)
        tabManager.structuralMutations
            .setSpacePinnedShortcuts([pin], for: space.id)
        let firstLiveTab = tabManager.makeLiveTab(
            pin,
            in: firstWindow.id,
            currentSpaceId: space.id
        )!
        let secondLiveTab = tabManager.makeLiveTab(
            pin,
            in: secondWindow.id,
            currentSpaceId: space.id
        )!

        firstWindow.currentTabId = firstLiveTab.id
        firstWindow.currentShortcutPinId = pin.id
        firstWindow.currentShortcutPinRole = pin.role
        firstWindow.selectedShortcutPinForSpace[space.id] = pin.id
        secondWindow.currentTabId = UUID()
        secondWindow.selectedShortcutPinForSpace[space.id] = pin.id
        proxyWindow.currentTabId = pin.id
        proxyWindow.currentShortcutPinId = pin.id
        proxyWindow.currentShortcutPinRole = pin.role
        proxyWindow.selectedShortcutPinForSpace[space.id] = pin.id
        for windowState in windows {
            windowState.selectionHistory.recentSelectionItemsBySpace[space.id] = [
                .shortcutPin(pin.id),
            ]
        }
        let preservedSecondSelection = secondWindow.currentTabId

        XCTAssertTrue(tabManager.retireDeletedPin(pin.id))

        XCTAssertNil(
            tabManager.registry.tab(
                for: pin.id,
                in: firstWindow.id
            )
        )
        XCTAssertNil(
            tabManager.registry.tab(
                for: pin.id,
                in: secondWindow.id
            )
        )
        XCTAssertEqual(
            Set(probe.extensionClosedTabIds),
            [firstLiveTab.id, secondLiveTab.id]
        )
        XCTAssertEqual(
            probe.tabClosureBatches,
            []
        )
        XCTAssertNil(firstWindow.currentTabId)
        XCTAssertNil(firstWindow.currentShortcutPinId)
        XCTAssertEqual(secondWindow.currentTabId, preservedSecondSelection)
        XCTAssertNil(proxyWindow.currentTabId)
        XCTAssertNil(proxyWindow.currentShortcutPinId)
        for windowState in windows {
            XCTAssertNil(windowState.selectedShortcutPinForSpace[space.id])
            XCTAssertNil(
                windowState.selectionHistory
                    .recentSelectionItemsBySpace[space.id]
            )
        }
        XCTAssertEqual(probe.validationCount, 1)
        XCTAssertEqual(
            probe.persistedWindowIds,
            windows.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
        XCTAssertEqual(Set(probe.persistedWindowIds).count, windows.count)
    }

    func testDeletedPinCleansHistoryWithoutRequestingHistoryOnlyPersistence() {
        let spaceId = UUID()
        let pinId = UUID()
        let windowState = BrowserWindowState()
        windowState.currentTabId = UUID()
        windowState.selectionHistory.recentSelectionItemsBySpace[spaceId] = [
            .shortcutPin(pinId),
        ]

        let result = ShortcutSelectionReconciler.reconcileDeletedPin(
            pinId,
            in: windowState
        )

        XCTAssertNil(
            windowState.selectionHistory.recentSelectionItemsBySpace[spaceId]
        )
        XCTAssertFalse(result.didClearCurrentSelection)
        XCTAssertTrue(result.windowStatesNeedingPersistence.isEmpty)
    }

    func testDeletedPinPersistsRepairedAndMetadataOnlyWindowsOnce() throws {
        let selectedWindow = BrowserWindowState()
        let metadataOnlyWindow = BrowserWindowState()
        let windows = [selectedWindow, metadataOnlyWindow]
        let probe = RetirementProbe()
        let tabManager = try makeFixture(windows: windows, probe: probe)
        let space = try makeSpace(in: tabManager)
        let fallback = tabManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://fallback.example")!,
            spaceId: space.id
        )
        tabManager.membership.attach(fallback)
        let pin = makePin(spaceId: space.id)
        tabManager.structuralMutations
            .setSpacePinnedShortcuts([pin], for: space.id)
        windows.forEach {
            $0.currentSpaceId = space.id
        }

        let liveTab = tabManager.makeLiveTab(
            pin,
            in: selectedWindow.id,
            currentSpaceId: space.id
        )!
        selectedWindow.currentTabId = liveTab.id
        selectedWindow.currentShortcutPinId = pin.id
        selectedWindow.currentShortcutPinRole = pin.role
        metadataOnlyWindow.currentTabId = fallback.id
        metadataOnlyWindow.currentShortcutPinId = pin.id
        metadataOnlyWindow.currentShortcutPinRole = pin.role

        probe.validationAction = {
            selectedWindow.currentTabId = fallback.id
            probe.validatorPersistedWindowIds.append(selectedWindow.id)
        }
        probe.validatedWindowIds = [selectedWindow.id]

        XCTAssertTrue(tabManager.retireDeletedPin(pin.id))

        XCTAssertEqual(selectedWindow.currentTabId, fallback.id)
        XCTAssertNil(metadataOnlyWindow.currentShortcutPinId)
        XCTAssertEqual(
            Dictionary(
                grouping: probe.persistedWindowIds
                    + probe.validatorPersistedWindowIds,
                by: { $0 }
            )
                .mapValues(\.count),
            [selectedWindow.id: 1, metadataOnlyWindow.id: 1]
        )
    }

    private func makeFixture(
        windows: [BrowserWindowState],
        probe: RetirementProbe,
        retirement: TestRuntimePorts.RetirementCapabilities = .rejecting,
        receiveRuntimeAttachment: ((TabRuntimePortConnection) -> Void)? = nil
    ) throws -> RetirementFixture {
        let runtime = TestRuntimePorts.make(
            windowState: { windowId in
                windows.first { $0.id == windowId }
            },
            windows: { windows.map { ($0.id, $0) } },
            windowStates: { windows },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: retirement,
                unloadTab: { probe.unloadedTabIds.append($0.id) },
                requireRemoveAllWebViews: { _ in }
            ),
            handleTabClosures: { tabIds in
                probe.tabClosureBatches.append(tabIds)
            },
            notifyTabClosedIfLoaded: {
                probe.extensionClosedTabIds.append($0.id)
            },
            validateWindowStates: {
                probe.validationCount += 1
                probe.validationAction?()
                return probe.validatedWindowIds
            },
            persistWindowSession: {
                probe.persistedWindowIds.append($0.id)
            }
        )
        let fixture = try RetirementFixture(runtime: runtime)
        receiveRuntimeAttachment?(fixture.runtimeConnection)
        return fixture
    }

    private func makePin(spaceId: UUID) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: 0,
            launchURL: URL(string: "https://retirement.example")!,
            title: "Retirement"
        )
    }

    private func makeSpace(in fixture: RetirementFixture) throws -> Space {
        let space = Space(name: "Space")
        fixture.tabManager.stateStore.spaces.replaceSpaces([space])
        return space
    }
}

@MainActor
private final class RetirementFixture {
    let tabManager: TabManager
    let structuralLookup: TabStructuralLookupCoordinator
    let structuralMutations: TabStructuralCollectionMutationOwner
    let membership: TabCollectionMembershipOwner
    let registry: LiveShortcutTabRegistry
    let retirement: ShortcutLiveTabRetirementService

    var runtimeConnection: TabRuntimePortConnection {
        tabManager.runtimePortConnection
    }

    init(runtime: RuntimePortRegistry) throws {
        let container = try makeInMemoryStartupDatabase()
        let webViewSessions = WebViewSessionRepository()
        tabManager = TabManager(
            database: container,
            webViewSessions: webViewSessions,
            profileReferenceAdmission: try ProfileReferenceAdmissionLedger(
                database: container
            ),
            initialRuntimePorts: runtime,
            loadPersistedState: false
        )
        let state = tabManager.stateStore
        structuralLookup = TabStructuralLookupCoordinator(
            eventBus: tabManager.tabStructureEventBus,
            stateStore: state
        )
        let publisher = TabStructuralMutationPublisher(
            persistence: tabManager.structuralPersistence,
            faviconService: tabManager.faviconService,
            lookup: structuralLookup,
            changes: tabManager.objectWillChange,
            regularTabs: state.regularTabs
        )
        structuralMutations = TabStructuralCollectionMutationOwner(
            store: TabStructuralCollectionStore(
                regularTabs: state.regularTabs,
                folders: state.folders,
                shortcutPins: state.shortcutPins
            ),
            snapshots: TabStructuralCollectionSnapshotStore(
                regularTabs: state.regularTabs,
                folders: state.folders,
                shortcutPins: state.shortcutPins
            ),
            publisher: publisher
        )
        membership = TabCollectionMembershipOwner(
            structuralLookupOwner: structuralLookup.lookupOwner,
            state: state,
            runtimePreparation: TabRuntimePreparationOwner(
                runtimeConnection: tabManager.runtimePortConnection
            ),
            runtimeConnection: tabManager.runtimePortConnection
        )
        registry = LiveShortcutTabRegistry(
            storage: state.transientTabs,
            structuralLookup: structuralLookup
        )
        retirement = ShortcutLiveTabRetirementService(
            registry: registry,
            structuralLookup: structuralLookup,
            runtimeConnection: tabManager.runtimePortConnection,
            runtimeTeardown: TabRuntimeTeardownService(
                persistence: tabManager.structuralPersistence,
                membership: membership,
                webViewSessions: webViewSessions
            ),
            windowMutations: BrowserWindowShortcutMutationOwner(),
            splitGroups: state.splitGroups,
            splitMutations: SplitGroupMutationService(
                store: state.splitGroups,
                publication: publisher
            )
        )
    }

    func makeLiveTab(
        _ pin: ShortcutPin,
        in windowID: UUID,
        currentSpaceId: UUID
    ) -> Tab? {
        let tab = tabManager.tabFactory.makeTab(
            url: pin.launchURL,
            spaceId: currentSpaceId
        )
        tab.bindToShortcutPin(pin)
        membership.attach(tab)
        guard registry.register(
            tab,
            for: pin.id,
            in: windowID,
            presentationPage: LiveShortcutPresentationPageReceipt(
                windowID: windowID,
                spaceID: currentSpaceId,
                profileID: nil
            )
        ) else {
            membership.detach(tab)
            return nil
        }
        return tab
    }

    func retireDeletedPin(_ pinID: UUID) -> Bool {
        guard let prepared = retirement.prepareDeletedPinRetirement(pinID)
        else { return false }
        _ = retirement.finish(prepared)
        return true
    }
}

@MainActor
private final class RetirementProbe {
    var tabClosureBatches: [Set<UUID>] = []
    var extensionClosedTabIds: [UUID] = []
    var unloadedTabIds: [UUID] = []
    var destroyedGenerationTabIDs: [[UUID]] = []
    var persistedWindowIds: [UUID] = []
    var validatorPersistedWindowIds: [UUID] = []
    var validatedWindowIds = Set<UUID>()
    var validationCount = 0
    var validationAction: (() -> Void)?
}

private final class TabLifecycleNotificationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var notificationCount = 0
    private var observer: NSObjectProtocol?

    @MainActor
    init(tab: Tab) {
        observer = NotificationCenter.default.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: tab,
            queue: nil
        ) { [weak self] _ in
            self?.lock.withLock {
                self?.notificationCount += 1
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var count: Int {
        lock.withLock { notificationCount }
    }
}
