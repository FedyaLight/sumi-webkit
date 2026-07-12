import Combine
import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class ShortcutLiveTabRetirementServiceTests: XCTestCase {
    func testMissingRuntimeLeavesLiveRegistryUnchanged() throws {
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = makePin(spaceId: space.id)
        let windowId = UUID()
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )

        tabManager.tabClosureService.removeTab(liveTab.id)

        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: windowId),
            liveTab
        )
    }

    func testGenericTabRemovalDelegatesLiveShortcutToCanonicalRetirementOnce() throws {
        let windowState = BrowserWindowState()
        let probe = RetirementProbe()
        let tabManager = try makeTabManager(windows: [windowState], probe: probe)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = makePin(spaceId: space.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )

        tabManager.tabClosureService.removeTab(liveTab.id)

        XCTAssertNil(tabManager.liveShortcutTabs.entry(tabId: liveTab.id))
        XCTAssertEqual(probe.tabClosureBatches, [[liveTab.id]])
        XCTAssertEqual(probe.unloadedTabIds, [liveTab.id])
        XCTAssertEqual(probe.extensionClosedTabIds, [liveTab.id])
    }

    func testGenericRemovalValidatesClearedSelectedShortcut() throws {
        let windowState = BrowserWindowState()
        let probe = RetirementProbe()
        let tabManager = try makeTabManager(
            windows: [windowState],
            probe: probe
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = makePin(spaceId: space.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        windowState.currentSpaceId = space.id
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role

        tabManager.tabClosureService.removeTab(liveTab.id)

        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertEqual(probe.validationCount, 1)
    }

    func testPreparedRuntimeLeaseSurvivesDetachFromStructuralSubscriber() throws {
        let windowState = BrowserWindowState()
        let probe = RetirementProbe()
        let tabManager = try makeTabManager(
            windows: [windowState],
            probe: probe
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = makePin(spaceId: space.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { [weak tabManager] _ in
                tabManager?.detachBrowserRuntime()
            }

        let result = tabManager.shortcutLiveTabRetirement.retire(
            pinId: pin.id,
            in: windowState.id
        )

        XCTAssertTrue(result.didRetire)
        XCTAssertNil(tabManager.runtimePorts)
        XCTAssertEqual(probe.unloadedTabIds, [liveTab.id])
        _ = cancellable
    }

    func testBackgroundRetirementReportsSuccessAndRunsCompleteTeardownOnce() throws {
        let windowState = BrowserWindowState()
        let probe = RetirementProbe()
        let tabManager = try makeTabManager(
            windows: [windowState],
            probe: probe
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = makePin(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: space.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        let unrelatedSelection = UUID()
        windowState.currentTabId = unrelatedSelection
        windowState.selectedShortcutPinForSpace[space.id] = pin.id
        windowState.selectionHistory.recentSelectionItemsBySpace[space.id] = [
            .shortcutPin(pin.id),
        ]
        let lifecycle = TabLifecycleNotificationRecorder(tab: liveTab)

        let retirement = tabManager.shortcutLiveTabRetirement.retire(
            pinId: pin.id,
            in: windowState.id
        )
        let repeatedRetirement = tabManager.shortcutLiveTabRetirement.retire(
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
            tabManager.shortcutPresentationOwner.shortcutLiveTab(
                for: pin.id,
                in: windowState.id
            )
        )
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id))
        XCTAssertEqual(probe.tabClosureBatches, [[liveTab.id]])
        XCTAssertEqual(probe.extensionClosedTabIds, [liveTab.id])
        XCTAssertEqual(probe.unloadedTabIds, [liveTab.id])
        XCTAssertEqual(
            probe.removeAllWebViewsCalls.map(\.tabId),
            [liveTab.id]
        )
        XCTAssertEqual(
            probe.removeAllWebViewsCalls.map(\.closeFullscreen),
            [true]
        )
        XCTAssertEqual(lifecycle.count, 1)
    }

    func testDeletedPinRetiresEveryWindowInstanceAndPersistsEachChangedWindowOnce() throws {
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        let proxyWindow = BrowserWindowState()
        let windows = [firstWindow, secondWindow, proxyWindow]
        let probe = RetirementProbe()
        let tabManager = try makeTabManager(windows: windows, probe: probe)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = makePin(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: space.id)
        let firstLiveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: firstWindow.id,
            currentSpaceId: space.id
        )
        let secondLiveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: secondWindow.id,
            currentSpaceId: space.id
        )

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

        tabManager.shortcutPinCommandOwner.removeShortcutPin(pin)

        XCTAssertNil(
            tabManager.shortcutPresentationOwner.shortcutLiveTab(
                for: pin.id,
                in: firstWindow.id
            )
        )
        XCTAssertNil(
            tabManager.shortcutPresentationOwner.shortcutLiveTab(
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
            [[firstLiveTab.id, secondLiveTab.id]]
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
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let fallback = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://fallback.example",
            in: space,
            activate: false
        )
        let pin = makePin(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: space.id)
        windows.forEach {
            $0.tabManager = tabManager
            $0.currentSpaceId = space.id
        }

        var persistedWindowIds: [UUID] = []
        let validator = makeWindowStateReconciler(
            tabManager: tabManager,
            windows: windows,
            persist: { persistedWindowIds.append($0.id) }
        )
        let statesById = Dictionary(
            uniqueKeysWithValues: windows.map { ($0.id, $0) }
        )
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                windowState: { statesById[$0] },
                windows: { windows.map { ($0.id, $0) } },
                windowStates: { windows },
                validateWindowStates: validator.validateWindowStates,
                persistWindowSession: { persistedWindowIds.append($0.id) }
            )
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: selectedWindow.id,
            currentSpaceId: space.id
        )
        selectedWindow.currentTabId = liveTab.id
        selectedWindow.currentShortcutPinId = pin.id
        selectedWindow.currentShortcutPinRole = pin.role
        metadataOnlyWindow.currentTabId = fallback.id
        metadataOnlyWindow.currentShortcutPinId = pin.id
        metadataOnlyWindow.currentShortcutPinRole = pin.role

        tabManager.shortcutPinCommandOwner.removeShortcutPin(pin)

        XCTAssertEqual(selectedWindow.currentTabId, fallback.id)
        XCTAssertNil(metadataOnlyWindow.currentShortcutPinId)
        XCTAssertEqual(
            Dictionary(grouping: persistedWindowIds, by: { $0 })
                .mapValues(\.count),
            [selectedWindow.id: 1, metadataOnlyWindow.id: 1]
        )
    }

    private func makeTabManager(
        windows: [BrowserWindowState],
        probe: RetirementProbe
    ) throws -> TabManager {
        let runtime = TestRuntimePorts.make(
            windowState: { windowId in
                windows.first { $0.id == windowId }
            },
            windows: { windows.map { ($0.id, $0) } },
            windowStates: { windows },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                unloadTab: { probe.unloadedTabIds.append($0.id) },
                requireRemoveAllWebViews: { tab, closeFullscreen in
                    probe.removeAllWebViewsCalls.append(
                        (tab.id, closeFullscreen)
                    )
                }
            ),
            handleTabClosures: { tabIds in
                probe.tabClosureBatches.append(tabIds)
            },
            notifyTabClosedIfLoaded: {
                probe.extensionClosedTabIds.append($0.id)
            },
            validateWindowStates: {
                probe.validationCount += 1
                return []
            },
            persistWindowSession: {
                probe.persistedWindowIds.append($0.id)
            }
        )
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            runtimePorts: runtime,
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        windows.forEach { $0.tabManager = tabManager }
        return tabManager
    }

    private func makeWindowStateReconciler(
        tabManager: TabManager,
        windows: [BrowserWindowState],
        persist: @escaping (BrowserWindowState) -> Void
    ) -> BrowserWindowStateReconciler {
        let spaceContext = BrowserWindowSpaceContextReconciler(
            tabManager: tabManager,
            commitWorkspaceTheme: { _, _ in /* No-op. */ }
        )
        let selectionRepair = BrowserWindowSelectionRepairService(
            tabManager: tabManager,
            selection: ShellSelectionService(splitTabsForWindow: { _ in [] }),
            synchronizeShortcutSelection: { _ in /* No-op. */ },
            applyTabSelection: { tab, windowState in
                _ = WindowTabSelectionStateApplicator.apply(
                    tab,
                    to: windowState,
                    updateSpaceFromTab: false,
                    rememberSelection: false
                )
            },
            showEmptyState: { windowState in
                windowState.currentTabId = nil
                windowState.isShowingEmptyState = true
            }
        )
        return BrowserWindowStateReconciler(
            windows: { windows },
            spaceContext: spaceContext,
            selectionRepair: selectionRepair,
            focusedRuntime: FocusedSpaceRuntimeStateSynchronizer(
                activeWindow: { windows.first },
                windowContext: spaceContext,
                runtimeState: tabManager.profileRuntimeState
            ),
            persistWindowSession: persist,
            refreshCompositor: { _ in /* No-op. */ }
        )
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
}

@MainActor
private final class RetirementProbe {
    var tabClosureBatches: [Set<UUID>] = []
    var extensionClosedTabIds: [UUID] = []
    var unloadedTabIds: [UUID] = []
    var removeAllWebViewsCalls: [(tabId: UUID, closeFullscreen: Bool)] = []
    var persistedWindowIds: [UUID] = []
    var validationCount = 0
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
