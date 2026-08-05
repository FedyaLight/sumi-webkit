import AppKit
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowLifecycleWorkflowTests: XCTestCase {
    func testWindowCloseDismissesGlanceOwnedByClosingWindow() async throws {
        let browserManager = BrowserManager()
        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(in: browserManager.spaceStateOwner, name: "Glance Window Close")
        let sourceTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example/page",
            in: space,
            activate: false
        )
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = sourceTab.id
        browserManager.windowRegistry.register(windowState)
        browserManager.windowRegistry.setActive(windowState)

        let url = try XCTUnwrap(URL(string: "https://destination.example/page"))
        XCTAssertTrue(
            browserManager.glanceManager.presentExternalURL(
                url,
                from: sourceTab,
                in: windowState
            )
        )
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        for _ in 0..<20 {
            if previewTab.resolvedCurrentWebView() != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(previewTab.resolvedCurrentWebView())

        let windowSession = browserManager.windowSessionBundle
        let workflow = BrowserWindowCloseWorkflow(
            browserRuntime: browserManager,
            recorder: windowSession.history.recorder,
            persistence: browserManager.windowSessionPersistenceCoordinator,
            extensions: browserManager.optionalModules.extensions,
            webViews: browserManager.testWebViewRuntime().lifecycleService,
            emptySplitPlaceholders: browserManager.splitEmptyPlaceholders,
            splitPreviews: browserManager.splitWindowContext.previews,
            commands: browserManager.windowCommands
        )

        workflow.handleWindowClose(windowState)

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertNil(previewTab.resolvedCurrentWebView())
    }

    func testCloseWorkflowCleansEveryCanonicalWebViewResidenceAfterRuntimeRelease() throws {
        var browserManager: BrowserManager? = BrowserManager()
        let repository = try XCTUnwrap(browserManager?.webViewSessions)
        let webViewRuntime = try XCTUnwrap(browserManager?.testWebViewRuntime())
        let windowState = BrowserWindowState()
        let trackedTabID = UUID()
        let parkedTabID = UUID()
        let untrackedTabID = UUID()
        let pendingTabID = UUID()
        let tracked = FocusableWKWebView()
        let parked = WKWebView()
        let untracked = WKWebView()
        let pending = WKWebView()
        let trackedTab = Tab(
            id: trackedTabID,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        tracked.owningTab = trackedTab
        let workflow: BrowserWindowCloseWorkflow

        do {
            let browserManager = try XCTUnwrap(browserManager)
            let windowSession = browserManager.windowSessionBundle
            workflow = BrowserWindowCloseWorkflow(
                browserRuntime: browserManager,
                recorder: windowSession.history.recorder,
                persistence: browserManager.windowSessionPersistenceCoordinator,
                extensions: browserManager.optionalModules.extensions,
                webViews: webViewRuntime.lifecycleService,
                emptySplitPlaceholders: browserManager.splitEmptyPlaceholders,
                splitPreviews: browserManager.splitWindowContext.previews,
                commands: browserManager.windowCommands
            )
        }

        webViewRuntime.trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
            tracked,
            for: trackedTab,
            in: windowState.id
        )
        WebViewSessionHandle(
            tabID: parkedTabID,
            repository: repository
        ).park(parked)
        WebViewSessionHandle(
            tabID: untrackedTabID,
            repository: repository
        ).replaceUntracked(with: untracked)
        XCTAssertNotNil(repository.beginPendingCleanup(of: pending, for: pendingTabID))
        webViewRuntime.protectionRuntime.beginHistorySwipe(
            tabID: trackedTabID,
            webView: tracked,
            originURL: nil,
            originHistoryItem: nil
        )
        XCTAssertTrue(
            webViewRuntime.protectionRuntime.hasActiveHistorySwipe(in: windowState.id)
        )

        weak let releasedBrowserManager = browserManager
        browserManager = nil
        XCTAssertNil(releasedBrowserManager)

        workflow.handleWindowClose(windowState)

        XCTAssertTrue(repository.queries.isTrackingEmpty)
        for webView in [tracked, parked, untracked, pending] {
            XCTAssertNil(repository.residence(of: webView))
        }
        XCTAssertFalse(
            webViewRuntime.protectionRuntime.hasActiveHistorySwipe(in: windowState.id)
        )

        webViewRuntime.lifecycleService.cleanupWindow(windowState.id)

        XCTAssertTrue(repository.queries.isTrackingEmpty)
        XCTAssertFalse(
            webViewRuntime.protectionRuntime.hasActiveHistorySwipe(in: windowState.id)
        )
    }

    func testWindowCloseRecordsHistoryAndRefreshesArchiveExcludingClosedWindow() throws {
        let browserManager = BrowserManager()
        let webViewRuntime = browserManager.testWebViewRuntime()
        let registry = browserManager.windowRegistry
        let closingWindow = BrowserWindowState()
        closingWindow.currentTabId = UUID()
        let survivingWindow = BrowserWindowState()
        survivingWindow.currentTabId = UUID()
        registry.register(closingWindow)
        registry.register(survivingWindow)
        let snapshotFactory = WindowSessionSnapshotFactory(
            glanceManager: browserManager.glanceManager
        )
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "BrowserWindowLifecycleWorkflowTests"
        )
        let recentlyClosed = RecentlyClosedManager()
        let catalog = OpenWindowSessionCatalog(
            windows: registry,
            snapshots: snapshotFactory
        )
        let recorder = ClosedWindowHistoryRecorder(
            snapshots: snapshotFactory,
            titles: ClosedWindowDisplayTitleProjection(
                windowTabs: browserManager.windowTabContext,
                spaces: browserManager.spaceStateOwner
            ),
            recentlyClosedManager: recentlyClosed
        )
        let archive = LastSessionWindowArchive(
            openWindows: catalog,
            lastSessionWindowsStore: store,
            startupRestore: StartupSessionRestoreProviderFake()
        )
        let persistence = makeClosePersistence(
            catalog: catalog,
            archive: archive,
            browserManager: browserManager
        )
        let workflow = BrowserWindowCloseWorkflow(
            browserRuntime: browserManager,
            recorder: recorder,
            persistence: persistence,
            extensions: browserManager.optionalModules.extensions,
            webViews: webViewRuntime.lifecycleService,
            emptySplitPlaceholders: browserManager.splitEmptyPlaceholders,
            splitPreviews: browserManager.splitWindowContext.previews,
            commands: browserManager.windowCommands
        )

        workflow.handleWindowClose(closingWindow)

        guard case .window(let closedItem)? = recentlyClosed.items.first else {
            return XCTFail("Expected the closed window in recently-closed history")
        }
        XCTAssertEqual(closedItem.title, "Window")
        XCTAssertEqual(closedItem.session, snapshotFactory.make(for: closingWindow))
        XCTAssertEqual(
            store.snapshots,
            [
                LastSessionWindowSnapshot(
                    id: survivingWindow.id,
                    session: snapshotFactory.make(for: survivingWindow)
                ),
            ]
        )
    }

    func testIncognitoClosePreservesRegularHistoryArchive() async throws {
        let browserManager = BrowserManager()
        let webViewRuntime = browserManager.testWebViewRuntime()
        let registry = browserManager.windowRegistry
        browserManager.windowShellContentViewFactory = { _, _ in NSView() }
        let incognitoWindow = BrowserWindowState()
        let profile = browserManager.profileManager.createEphemeralProfile(
            for: incognitoWindow.id
        )
        incognitoWindow.isIncognito = true
        browserManager.tabResidenceAuthority.establishResidenceSession(on: incognitoWindow)
        incognitoWindow.ephemeralProfile = profile
        incognitoWindow.currentProfileId = profile.id
        registry.register(incognitoWindow)
        let survivingWindow = BrowserWindowState()
        survivingWindow.currentTabId = UUID()
        registry.register(survivingWindow)
        let snapshotFactory = WindowSessionSnapshotFactory(
            glanceManager: browserManager.glanceManager
        )
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "BrowserWindowLifecycleWorkflowTests"
        )
        let archivedSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        store.updateSnapshots([archivedSnapshot])
        let recentlyClosed = RecentlyClosedManager()
        let catalog = OpenWindowSessionCatalog(
            windows: registry,
            snapshots: snapshotFactory
        )
        let archive = LastSessionWindowArchive(
            openWindows: catalog,
            lastSessionWindowsStore: store,
            startupRestore: StartupSessionRestoreProviderFake()
        )
        let workflow = BrowserWindowCloseWorkflow(
            browserRuntime: browserManager,
            recorder: ClosedWindowHistoryRecorder(
                snapshots: snapshotFactory,
                titles: ClosedWindowDisplayTitleProjection(
                    windowTabs: browserManager.windowTabContext,
                    spaces: browserManager.spaceStateOwner
                ),
                recentlyClosedManager: recentlyClosed
            ),
            persistence: makeClosePersistence(
                catalog: catalog,
                archive: archive,
                browserManager: browserManager
            ),
            extensions: browserManager.optionalModules.extensions,
            webViews: webViewRuntime.lifecycleService,
            emptySplitPlaceholders: browserManager.splitEmptyPlaceholders,
            splitPreviews: browserManager.splitWindowContext.previews,
            commands: browserManager.windowCommands
        )

        let cleanup = workflow.handleWindowClose(incognitoWindow)

        XCTAssertTrue(recentlyClosed.items.isEmpty)
        XCTAssertEqual(store.snapshots, [archivedSnapshot])
        await cleanup?.value
        XCTAssertNil(incognitoWindow.ephemeralProfile)
    }

    func testAllWindowsClosedCleanupUsesSynchronousProfileSnapshot() async {
        let browserManager = BrowserManager()
        let initialProfile = Profile(name: "Initial")
        let laterProfile = Profile(name: "Later")
        browserManager.profileManager.profiles = [initialProfile]
        let siteDataPolicy = RecordingWindowCloseSiteDataPolicy()
        let workflow = BrowserAllWindowsClosedWorkflow(
            browserRuntime: browserManager,
            sessionRestore: browserManager.windowSessionBundle.restoreService,
            siteDataPolicy: siteDataPolicy,
            profiles: browserManager.profileManager
        )

        workflow.handleAllWindowsClosed()
        browserManager.profileManager.profiles.append(laterProfile)

        await siteDataPolicy.waitForCleanup()
        XCTAssertEqual(siteDataPolicy.cleanedProfileIDs, [initialProfile.id])
    }

    func testAcceptedSiteDataCleanupKeepsRuntimeAliveUntilParticipantsFinish() async throws {
        var browserManager: BrowserManager? = BrowserManager()
        let siteDataPolicy = GatedWindowCloseSiteDataPolicy()
        let workflow: BrowserAllWindowsClosedWorkflow

        do {
            let browserManager = try XCTUnwrap(browserManager)
            workflow = BrowserAllWindowsClosedWorkflow(
                browserRuntime: browserManager,
                sessionRestore: browserManager.windowSessionBundle.restoreService,
                siteDataPolicy: siteDataPolicy,
                profiles: browserManager.profileManager
            )
        }

        workflow.handleAllWindowsClosed()
        await siteDataPolicy.waitUntilStarted()

        weak let releasedBrowserManager = browserManager
        browserManager = nil
        XCTAssertNotNil(releasedBrowserManager)

        siteDataPolicy.finishCleanup()
        await siteDataPolicy.waitUntilFinished()
        XCTAssertNil(releasedBrowserManager)
    }

    func testIncognitoCloseKeepsExactRuntimeAliveUntilAsyncCleanupFinishes() async throws {
        var browserManager: BrowserManager? = BrowserManager()
        let registry = try XCTUnwrap(browserManager).windowRegistry
        let windowState = BrowserWindowState()
        let workflow: BrowserWindowCloseWorkflow

        do {
            let browserManager = try XCTUnwrap(browserManager)
            let webViewRuntime = browserManager.testWebViewRuntime()
            browserManager.windowShellContentViewFactory = { _, _ in NSView() }
            let profile = browserManager.profileManager.createEphemeralProfile(
                for: windowState.id
            )
            let space = Space(name: "Incognito", profileId: profile.id)
            space.isEphemeral = true
            windowState.isIncognito = true
            browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
            windowState.ephemeralProfile = profile
            windowState.replaceEphemeralSpaces([space])
            windowState.currentProfileId = profile.id
            windowState.currentSpaceId = space.id
            registry.register(windowState)

            let windowSession = browserManager.windowSessionBundle
            workflow = BrowserWindowCloseWorkflow(
                browserRuntime: browserManager,
                recorder: windowSession.history.recorder,
                persistence: browserManager.windowSessionPersistenceCoordinator,
                extensions: browserManager.optionalModules.extensions,
                webViews: webViewRuntime.lifecycleService,
                emptySplitPlaceholders: browserManager.splitEmptyPlaceholders,
                splitPreviews: browserManager.splitWindowContext.previews,
                commands: browserManager.windowCommands
            )
        }

        let cleanup = workflow.handleWindowClose(windowState)
        weak let releasedBrowserManager = browserManager
        browserManager = nil

        XCTAssertNotNil(releasedBrowserManager)
        await cleanup?.value
        XCTAssertNil(windowState.ephemeralProfile)
        XCTAssertNil(releasedBrowserManager)
        XCTAssertTrue(windowState.ephemeralSpaces.isEmpty)
        XCTAssertNil(windowState.currentSpaceId)
    }

    func testInstalledWindowCallbacksDoNotRetainRegistry() throws {
        let browserManager = BrowserManager()
        let webViewRuntime = browserManager.testWebViewRuntime()
        let windowSession = browserManager.windowSessionBundle
        let closeWorkflow = BrowserWindowCloseWorkflow(
            browserRuntime: browserManager,
            recorder: windowSession.history.recorder,
            persistence: browserManager.windowSessionPersistenceCoordinator,
            extensions: browserManager.optionalModules.extensions,
            webViews: webViewRuntime.lifecycleService,
            emptySplitPlaceholders: browserManager.splitEmptyPlaceholders,
            splitPreviews: browserManager.splitWindowContext.previews,
            commands: browserManager.windowCommands
        )
        let allClosedWorkflow = BrowserAllWindowsClosedWorkflow(
            browserRuntime: browserManager,
            sessionRestore: windowSession.restoreService,
            siteDataPolicy: browserManager.dataServices.siteDataPolicyEnforcementService,
            profiles: browserManager.profileManager
        )
        var registry: WindowRegistry? = WindowRegistry()
        weak let releasedRegistry = registry

        BrowserWindowRegistryBinding.install(
            registration: windowSession.restoration,
            closing: closeWorkflow,
            activity: browserManager.windowActivation,
            allWindowsClosed: allClosedWorkflow,
            on: try XCTUnwrap(registry)
        )
        registry = nil

        XCTAssertNil(releasedRegistry)
    }

    func testWindowRegistryCloseCallbackReceivesClaimedStateAfterRemoval() {
        let registry = WindowRegistry()
        let windowState = BrowserWindowState()
        var receivedState: BrowserWindowState?
        var wasAlreadyDetached = false
        var events: [String] = []

        installWindowRegistryTestEventSink(
            on: registry,
            closeWindow: { closingState in
                receivedState = closingState
                wasAlreadyDetached = registry.windows[closingState.id] == nil
                events.append("close")
            },
            closeAllWindows: { events.append("allClosed") }
        )
        registry.register(windowState)

        registry.unregister(windowState.id)

        XCTAssertIdentical(receivedState, windowState)
        XCTAssertTrue(wasAlreadyDetached)
        XCTAssertEqual(events, ["close", "allClosed"])
        XCTAssertNil(registry.windows[windowState.id])
    }

    private func makeClosePersistence(
        catalog: OpenWindowSessionCatalog,
        archive: LastSessionWindowArchive,
        browserManager: BrowserManager
    ) -> WindowSessionPersistenceCoordinator {
        let suiteName = "BrowserWindowLifecycleWorkflowTests.Persistence.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Failed to create persistence test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let snapshotFactory = WindowSessionSnapshotFactory(
            glanceManager: browserManager.glanceManager
        )
        return WindowSessionPersistenceCoordinator(
            snapshotStore: WindowSessionSnapshotStore(
                key: "window-session",
                environment: { [:] }
            ),
            snapshotFactory: snapshotFactory,
            scheduler: WindowSessionPersistenceScheduler(),
            openWindows: catalog,
            archive: archive
        )
    }
}

@MainActor
private final class RecordingWindowCloseSiteDataPolicy: BrowserSiteDataPolicyEnforcing {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var didPerformCleanup = false
    private(set) var cleanedProfileIDs: [UUID] = []

    func attachDestructiveCleanupPreparer(
        _: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    ) { /* No-op. */ }

    func setBlockStorage(
        _: Bool,
        forHost _: String,
        profile _: Profile?
    ) async { /* No-op. */ }

    func setDeleteWhenAllWindowsClosed(
        _: Bool,
        forHost _: String,
        profile _: Profile?
    ) { /* No-op. */ }

    func enforceBlockStorageIfNeeded(for _: URL?, profile _: Profile?) { /* No-op. */ }

    func performAllWindowsClosedCleanup(profiles: [Profile]) async {
        didPerformCleanup = true
        cleanedProfileIDs = profiles.map(\.id)
        let waiters = waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitForCleanup() async {
        guard didPerformCleanup == false else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

@MainActor
private final class GatedWindowCloseSiteDataPolicy: BrowserSiteDataPolicyEnforcing {
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var cleanupContinuation: CheckedContinuation<Void, Never>?
    private var started = false
    private var finished = false

    func attachDestructiveCleanupPreparer(
        _: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    ) { /* No-op. */ }

    func setBlockStorage(
        _: Bool,
        forHost _: String,
        profile _: Profile?
    ) async { /* No-op. */ }

    func setDeleteWhenAllWindowsClosed(
        _: Bool,
        forHost _: String,
        profile _: Profile?
    ) { /* No-op. */ }

    func enforceBlockStorageIfNeeded(for _: URL?, profile _: Profile?) { /* No-op. */ }

    func performAllWindowsClosedCleanup(profiles _: [Profile]) async {
        started = true
        let startWaiters = startWaiters
        self.startWaiters.removeAll()
        startWaiters.forEach { $0.resume() }
        await withCheckedContinuation { cleanupContinuation = $0 }
        finished = true
        let finishWaiters = finishWaiters
        self.finishWaiters.removeAll()
        finishWaiters.forEach { $0.resume() }
    }

    func waitUntilStarted() async {
        guard started == false else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finishCleanup() {
        cleanupContinuation?.resume()
        cleanupContinuation = nil
    }

    func waitUntilFinished() async {
        guard finished == false else { return }
        await withCheckedContinuation { finishWaiters.append($0) }
    }
}
