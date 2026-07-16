import AppKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserAppOrchestrationOwnerTests: XCTestCase {
    func testSetupWiresApplicationRuntimeDependenciesOnce() {
        let harness = makeHarness()

        let firstSetup = harness.owner.setupIfNeeded(dependencies: harness.dependencies)
        let secondSetup = harness.owner.setupIfNeeded(dependencies: harness.dependencies)

        XCTAssertTrue(firstSetup)
        XCTAssertFalse(secondSetup)
        XCTAssertIdentical(harness.appDelegate.windowRegistry, harness.windowRegistry)
        XCTAssertNotNil(harness.appDelegate.mouseButtonRouter)
        XCTAssertIdentical(
            harness.appDelegate.tabCommandRouter,
            harness.browserManager.tabLifecycleService.closeOrchestration
        )
        XCTAssertIdentical(
            harness.appDelegate.windowRouter,
            harness.browserManager.windowCommands
        )
        XCTAssertTrue(
            harness.appDelegate.externalURLHandler is ExternalURLTabOpeningService
        )
        XCTAssertNotNil(harness.appDelegate.terminationCoordinator)
        XCTAssertNotNil(harness.appDelegate.appLifecycleHandler)
        XCTAssertNotIdentical(harness.appDelegate.appLifecycleHandler as AnyObject?, harness.browserManager)
        XCTAssertIdentical(harness.appDelegate.settingsHandler, harness.settingsManager)
        XCTAssertIdentical(harness.appDelegate.shortcutManager, harness.keyboardShortcutManager)
        XCTAssertIdentical(
            harness.dependencies.webViewLifecycle,
            harness.browserManager.webViewRuntime.lifecycleService
        )
        XCTAssertIdentical(harness.browserManager.windowRegistry, harness.windowRegistry)
        XCTAssertIdentical(harness.browserManager.sumiSettings, harness.settingsManager)
        XCTAssertIdentical(
            harness.browserManager.keyboardShortcutManager,
            harness.keyboardShortcutManager
        )
        XCTAssertIdentical(
            harness.browserManager.tabManager.runtimePorts?.settings,
            harness.settingsManager
        )
        XCTAssertNotNil(harness.browserManager.windowShellContentViewFactory)
        XCTAssertEqual(harness.startUpdaterCallCount(), 1)
    }

    func testSetupInstallsWindowRegistryCallbacks() {
        let harness = makeHarness()

        harness.owner.setupIfNeeded(dependencies: harness.dependencies)

        XCTAssertTrue(harness.windowRegistry.hasInstalledEventSink)
    }

    func testSetupRejectsPreinstalledRegistrySinkBeforeMutatingAppGraph() {
        let harness = makeHarness()
        installWindowRegistryTestEventSink(on: harness.windowRegistry)

        XCTAssertFalse(
            harness.owner.setupIfNeeded(dependencies: harness.dependencies)
        )
        XCTAssertNil(harness.appDelegate.windowRegistry)
        XCTAssertNil(harness.browserManager.windowRegistry)
        XCTAssertEqual(harness.startUpdaterCallCount(), 0)
    }

    func testSetupRestoresExistingAndFutureWindowRegistrations() {
        let harness = makeHarness()
        let existingWindow = BrowserWindowState()
        let futureWindow = BrowserWindowState()
        harness.windowRegistry.register(existingWindow)

        harness.owner.setupIfNeeded(dependencies: harness.dependencies)
        harness.windowRegistry.register(futureWindow)

        XCTAssertIdentical(existingWindow.tabManager, harness.browserManager.tabManager)
        XCTAssertIdentical(futureWindow.tabManager, harness.browserManager.tabManager)
    }

    func testSetupReplacesShortcutManagerExtensionHandlerWithBrowserRuntimeHandler() throws {
        let harness = makeHarness()
        harness.keyboardShortcutManager.extensionCommandHandler = { _ in true }

        harness.owner.setupIfNeeded(dependencies: harness.dependencies)

        let event = try XCTUnwrap(Self.makeKeyDownEvent())
        XCTAssertFalse(harness.keyboardShortcutManager.extensionCommandHandler(event))
    }

    func testFullSetupGraphReleasesBrowserManagerAndDisablesLateMouseCommands() async throws {
        let owner = BrowserAppOrchestrationOwner()
        let appDelegate = AppDelegate()
        let nowPlayingController = SumiNativeNowPlayingController()
        let settings = SumiSettingsService(nowPlayingController: nowPlayingController)
        let registry = WindowRegistry()
        let shortcuts = KeyboardShortcutManager(installEventMonitor: false)
        var browserManager: BrowserManager? = BrowserManager(
            nowPlayingController: nowPlayingController
        )
        weak let releasedBrowserManager = browserManager
        weak var releasedRestorationService: BrowserWindowSessionRestorationService?
        weak var releasedActivationService: BrowserWindowActivationService?
        weak var releasedWindowExtensionPublication:
            WindowExtensionPublicationTransaction?
        weak var releasedTabManager: TabManager?
        weak var releasedProfileManager: ProfileManager?

        do {
            let browserManager = try XCTUnwrap(browserManager)
            releasedTabManager = browserManager.tabManager
            releasedProfileManager = browserManager.profileManager
            releasedRestorationService = browserManager.windowSessionBundle.restoration
            releasedActivationService = browserManager.windowSessionBundle.activation
            releasedWindowExtensionPublication =
                browserManager.windowExtensionPublication
            let contentFactory: BrowserWindowShellService.ContentViewFactory = { [weak browserManager] _, _ in
                guard browserManager != nil else { return NSView() }
                return NSView()
            }
            owner.setupIfNeeded(
                dependencies: BrowserAppOrchestrationOwner.Dependencies(
                    appDelegate: appDelegate,
                    browserManager: browserManager,
                    windowRegistry: registry,
                    webViewLifecycle: browserManager.webViewRuntime.lifecycleService,
                    settingsManager: settings,
                    keyboardShortcutManager: shortcuts,
                    nowPlayingController: nowPlayingController,
                    windowShellContentViewFactory: contentFactory,
                    fallbackPersistenceSave: { /* No-op. */ },
                    startUpdater: { /* No-op. */ }
                )
            )
        }

        browserManager = nil

        XCTAssertNil(releasedBrowserManager)
        XCTAssertNil(releasedRestorationService)
        XCTAssertNil(releasedActivationService)
        XCTAssertNil(releasedWindowExtensionPublication)
        XCTAssertNil(releasedTabManager)
        XCTAssertNil(releasedProfileManager)
        XCTAssertNotNil(appDelegate.terminationCoordinator)
        XCTAssertNil(appDelegate.terminationCoordinator?.acquireFinalizationLease())
        let lateWindowState = BrowserWindowState()
        registry.register(lateWindowState)
        registry.setActive(lateWindowState)
        registry.notifyWindowVisibilityChanged(lateWindowState)
        appDelegate.mouseButtonRouter?.focusFloatingBar(
            in: lateWindowState,
            prefill: "late",
            navigateCurrentTab: true
        )
        XCTAssertFalse(lateWindowState.presentationState.isFloatingBarVisible)
        registry.unregister(lateWindowState.id)
    }

    func testRetainedCommandSurfacesReleaseLiveKernelAndIgnoreLateCalls() async throws {
        var browserManager: BrowserManager? = BrowserManager()
        let commands = DetachedBrowserCommandSurfaces(
            browserManager: try XCTUnwrap(browserManager)
        )

        browserManager = nil
        XCTAssertTrue(commands.hasReleasedLiveKernel)

        let lateWindow = BrowserWindowState()
        XCTAssertNil(commands.sidebarActions.spaceForSidebarActions(in: lateWindow))
        commands.nativeSurfaces.openNativeBrowserSurface(
            .settings,
            url: SettingsTabs.general.settingsSurfaceURL,
            in: lateWindow
        )
        XCTAssertNil(lateWindow.currentTabId)
        commands.zoom.cleanupZoomForTab(UUID())
        XCTAssertNil(commands.tabOpening.resolvedTabOpenSpace(for: .background()))

        let lateTab = Tab(
            url: URL(string: "https://late.example")!,
            name: "Late",
            loadsCachedFaviconOnInit: false
        )
        commands.tabClosing.closeTab(lateTab, in: lateWindow)
        XCTAssertNil(lateWindow.currentTabId)

        let targetSpaceID = UUID()
        lateWindow.presentationState.pendingSplitGroupFocusRequest = SplitGroupFocusRequest(
            groupID: UUID(),
            preferredMemberID: nil,
            targetSpaceID: targetSpaceID
        )
        commands.splitFocus.completePendingSplitGroupFocusIfReady(
            in: lateWindow,
            spaceId: targetSpaceID
        )
        XCTAssertNotNil(lateWindow.presentationState.pendingSplitGroupFocusRequest)

        commands.glance.presentExternalURL(
            URL(string: "https://late-glance.example")!,
            from: nil
        )
        XCTAssertNil(commands.glance.currentSession)
        let historyCount = commands.recentlyClosed.items.count
        commands.sessionRecovery.reopenMostRecentClosedItem()
        XCTAssertEqual(commands.recentlyClosed.items.count, historyCount)
    }

    private func makeHarness() -> Harness {
        let owner = BrowserAppOrchestrationOwner()
        let appDelegate = AppDelegate()
        let nowPlayingController = SumiNativeNowPlayingController()
        let settingsManager = SumiSettingsService(nowPlayingController: nowPlayingController)
        settingsManager.sidebarMiniPlayerEnabled = false
        let browserManager = BrowserManager(nowPlayingController: nowPlayingController)
        let windowRegistry = WindowRegistry()
        let keyboardShortcutManager = KeyboardShortcutManager(installEventMonitor: false)
        var startUpdaterCallCount = 0
        let factory: BrowserWindowShellService.ContentViewFactory = { _, _ in
            NSView()
        }
        let dependencies = BrowserAppOrchestrationOwner.Dependencies(
            appDelegate: appDelegate,
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            webViewLifecycle: browserManager.webViewRuntime.lifecycleService,
            settingsManager: settingsManager,
            keyboardShortcutManager: keyboardShortcutManager,
            nowPlayingController: nowPlayingController,
            windowShellContentViewFactory: factory,
            fallbackPersistenceSave: { /* No-op. */ },
            startUpdater: {
                startUpdaterCallCount += 1
            }
        )

        return Harness(
            owner: owner,
            appDelegate: appDelegate,
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            settingsManager: settingsManager,
            keyboardShortcutManager: keyboardShortcutManager,
            dependencies: dependencies,
            startUpdaterCallCount: { startUpdaterCallCount }
        )
    }

    private static func makeKeyDownEvent() -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "x",
            charactersIgnoringModifiers: "x",
            isARepeat: false,
            keyCode: 7
        )
    }
}

@MainActor
private struct Harness {
    let owner: BrowserAppOrchestrationOwner
    let appDelegate: AppDelegate
    let browserManager: BrowserManager
    let windowRegistry: WindowRegistry
    let settingsManager: SumiSettingsService
    let keyboardShortcutManager: KeyboardShortcutManager
    let dependencies: BrowserAppOrchestrationOwner.Dependencies
    let startUpdaterCallCount: () -> Int
}

@MainActor
private final class DetachedBrowserCommandSurfaces {
    weak var browserManager: BrowserManager?
    weak var tabManager: TabManager?
    weak var profileManager: ProfileManager?
    weak var zoomManager: ZoomManager?
    weak var liveFolderManager: SumiLiveFolderManager?
    weak var sessionRestore: WindowSessionRestoreService?

    let glance: GlanceManager
    let sidebarActions: BrowserSidebarActionOwner
    let nativeSurfaces: BrowserNativeSurfaceRoutingOwner
    let zoom: BrowserZoomCommandOwner
    let tabOpening: BrowserTabOpeningOwner
    let tabClosing: BrowserTabCloseOrchestrationOwner
    let splitFocus: SplitShortcutFocusService
    let sessionRecovery: BrowserSessionRecoveryCommands
    let recentlyClosed: RecentlyClosedManager

    var hasReleasedLiveKernel: Bool {
        browserManager == nil
            && tabManager == nil
            && profileManager == nil
            && zoomManager == nil
            && liveFolderManager == nil
            && sessionRestore == nil
    }

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
        self.tabManager = browserManager.tabManager
        self.profileManager = browserManager.profileManager
        self.zoomManager = browserManager.zoomManager
        self.liveFolderManager = browserManager.liveFolderManager
        self.sessionRestore = browserManager.windowSessionBundle.restoreService
        self.glance = browserManager.glanceManager
        self.sidebarActions = browserManager.chromeBundle.sidebarActionOwner
        self.nativeSurfaces = browserManager.chromeBundle.nativeSurfaceRoutingOwner
        self.zoom = browserManager.chromeBundle.zoomCommandOwner
        self.tabOpening = browserManager.tabLifecycleService.opening
        self.tabClosing = browserManager.tabLifecycleService.closeOrchestration
        self.splitFocus = browserManager.sidebarCommandService.splitShortcuts.focus
        self.sessionRecovery = browserManager.windowSessionBundle.sessionRecovery
        self.recentlyClosed = browserManager.recentlyClosedManager

        let closedTab = Tab(
            url: URL(string: "https://closed-before-release.example")!,
            name: "Closed before release",
            loadsCachedFaviconOnInit: false
        )
        recentlyClosed.captureClosedTab(
            closedTab,
            sourceSpaceId: nil,
            currentURL: closedTab.url,
            canGoBack: false,
            canGoForward: false
        )
    }
}
