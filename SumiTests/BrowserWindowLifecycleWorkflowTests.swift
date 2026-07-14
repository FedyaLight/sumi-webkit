import AppKit
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowLifecycleWorkflowTests: XCTestCase {
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
                persistence: windowSession.persistence,
                extensions: browserManager.optionalModules.extensions,
                webViews: webViewRuntime.lifecycleService,
                emptySplitPlaceholders: browserManager.splitComposition.emptyPlaceholders,
                splitPreviews: browserManager.splitComposition.previews,
                backgroundMedia: browserManager.backgroundMediaOptimizationService,
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

    func testWindowCloseRecordsHistoryThenRefreshesArchiveExcludingClosedWindow() throws {
        let browserManager = BrowserManager()
        let webViewRuntime = browserManager.testWebViewRuntime()
        let closingWindow = BrowserWindowState()
        let survivingWindow = BrowserWindowState()
        let closingSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let survivingSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let sessions = [
            closingWindow.id: closingSession,
            survivingWindow.id: survivingSession,
        ]
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "BrowserWindowLifecycleWorkflowTests"
        )
        let recentlyClosed = RecentlyClosedManager()
        var events: [String] = []
        let catalog = OpenWindowSessionCatalog(
            allWindows: { [closingWindow, survivingWindow] },
            makeWindowSessionSnapshot: { sessions[$0.id] }
        )
        let recorder = ClosedWindowHistoryRecorder(
            openWindows: catalog,
            windowDisplayTitle: { _ in "Closed Window" },
            recentlyClosedManager: {
                events.append("record")
                return recentlyClosed
            }
        )
        let archive = LastSessionWindowArchive(
            openWindows: catalog,
            lastSessionWindowsStore: {
                events.append("archiveRefresh")
                return store
            },
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
            emptySplitPlaceholders: browserManager.splitComposition.emptyPlaceholders,
            splitPreviews: browserManager.splitComposition.previews,
            backgroundMedia: browserManager.backgroundMediaOptimizationService,
            commands: browserManager.windowCommands
        )

        workflow.handleWindowClose(closingWindow)

        XCTAssertEqual(events, ["record", "archiveRefresh"])
        guard case .window(let closedItem)? = recentlyClosed.items.first else {
            return XCTFail("Expected the closed window in recently-closed history")
        }
        XCTAssertEqual(closedItem.title, "Closed Window")
        XCTAssertEqual(closedItem.session, closingSession)
        XCTAssertEqual(
            store.snapshots,
            [LastSessionWindowSnapshot(id: survivingWindow.id, session: survivingSession)]
        )
    }

    func testIncognitoClosePreservesRegularHistoryArchive() async throws {
        let browserManager = BrowserManager()
        let webViewRuntime = browserManager.testWebViewRuntime()
        let registry = WindowRegistry()
        browserManager.windowRegistry = registry
        browserManager.windowShellContentViewFactory = { _, _ in NSView() }
        let incognitoWindow = BrowserWindowState()
        let profile = browserManager.profileManager.createEphemeralProfile(
            for: incognitoWindow.id
        )
        incognitoWindow.isIncognito = true
        incognitoWindow.tabManager = browserManager.tabManager
        incognitoWindow.ephemeralProfile = profile
        incognitoWindow.currentProfileId = profile.id
        registry.register(incognitoWindow)
        let survivingWindow = BrowserWindowState()
        let survivingSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let sessions = [
            incognitoWindow.id: makeSessionRecoveryWindowSession(currentTabId: UUID()),
            survivingWindow.id: survivingSession,
        ]
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
            allWindows: { [incognitoWindow, survivingWindow] },
            makeWindowSessionSnapshot: { sessions[$0.id] }
        )
        let archive = LastSessionWindowArchive(
            openWindows: catalog,
            lastSessionWindowsStore: { store },
            startupRestore: StartupSessionRestoreProviderFake()
        )
        let workflow = BrowserWindowCloseWorkflow(
            browserRuntime: browserManager,
            recorder: ClosedWindowHistoryRecorder(
                openWindows: catalog,
                windowDisplayTitle: { _ in "Incognito" },
                recentlyClosedManager: { recentlyClosed }
            ),
            persistence: makeClosePersistence(
                catalog: catalog,
                archive: archive,
                browserManager: browserManager
            ),
            extensions: browserManager.optionalModules.extensions,
            webViews: webViewRuntime.lifecycleService,
            emptySplitPlaceholders: browserManager.splitComposition.emptyPlaceholders,
            splitPreviews: browserManager.splitComposition.previews,
            backgroundMedia: browserManager.backgroundMediaOptimizationService,
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
        let registry = WindowRegistry()
        let windowState = BrowserWindowState()
        let workflow: BrowserWindowCloseWorkflow

        do {
            let browserManager = try XCTUnwrap(browserManager)
            let webViewRuntime = browserManager.testWebViewRuntime()
            browserManager.windowRegistry = registry
            browserManager.windowShellContentViewFactory = { _, _ in NSView() }
            let profile = browserManager.profileManager.createEphemeralProfile(
                for: windowState.id
            )
            let space = Space(name: "Incognito", profileId: profile.id)
            space.isEphemeral = true
            windowState.isIncognito = true
            windowState.tabManager = browserManager.tabManager
            windowState.ephemeralProfile = profile
            windowState.replaceEphemeralSpaces([space])
            windowState.currentProfileId = profile.id
            windowState.currentSpaceId = space.id
            registry.register(windowState)

            let windowSession = browserManager.windowSessionBundle
            workflow = BrowserWindowCloseWorkflow(
                browserRuntime: browserManager,
                recorder: windowSession.history.recorder,
                persistence: windowSession.persistence,
                extensions: browserManager.optionalModules.extensions,
                webViews: webViewRuntime.lifecycleService,
                emptySplitPlaceholders: browserManager.splitComposition.emptyPlaceholders,
                splitPreviews: browserManager.splitComposition.previews,
                backgroundMedia: browserManager.backgroundMediaOptimizationService,
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
            persistence: windowSession.persistence,
            extensions: browserManager.optionalModules.extensions,
            webViews: webViewRuntime.lifecycleService,
            emptySplitPlaceholders: browserManager.splitComposition.emptyPlaceholders,
            splitPreviews: browserManager.splitComposition.previews,
            backgroundMedia: browserManager.backgroundMediaOptimizationService,
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
            activity: windowSession.activation,
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
        return WindowSessionPersistenceCoordinator(
            persistence: WindowSessionPersistenceService(
                store: WindowSessionSnapshotStore(
                    key: "window-session",
                    userDefaults: defaults,
                    environment: { [:] }
                ),
                snapshotFactory: WindowSessionSnapshotFactory(
                    glanceManager: browserManager.glanceManager
                )
            ),
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
