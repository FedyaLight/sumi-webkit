import Foundation

@MainActor
final class BrowserAppOrchestrationOwner {
    struct Dependencies {
        let appDelegate: AppDelegate
        let browserManager: BrowserManager
        let webViewLifecycle: WebViewLifecycleService
        let settingsManager: SumiSettingsService
        let keyboardShortcutManager: KeyboardShortcutManager
        let nowPlayingController: SumiNativeNowPlayingController
        let windowShellContentViewFactory: BrowserWindowShellService.ContentViewFactory
        let fallbackPersistenceSave: @MainActor () throws -> Void
        let startUpdater: @MainActor () -> Void
    }

    private weak var browserManager: BrowserManager?
    private weak var windowRegistry: WindowRegistry?
    private var mouseCommandRouter: BrowserMouseCommandRouter?
    private var externalURLTabOpening: ExternalURLTabOpeningService?
    private var windowRegistryEventSinkReceipt:
        WindowRegistry.EventSinkInstallationReceipt?
    private var didSetup = false

    @discardableResult
    func setupIfNeeded(dependencies: Dependencies) -> Bool {
        let windowRegistry = dependencies.browserManager.windowRegistry
        guard !didSetup,
              windowRegistry.canInstallEventSink
        else { return false }
        didSetup = true

        let appDelegate = dependencies.appDelegate
        let browserManager = dependencies.browserManager
        let settingsManager = dependencies.settingsManager
        let keyboardShortcutManager = dependencies.keyboardShortcutManager
        let nowPlayingController = dependencies.nowPlayingController

        self.browserManager = browserManager
        self.windowRegistry = windowRegistry
        appDelegate.windowRegistry = windowRegistry
        appDelegate.appLifecycleOwner = self
        appDelegate.settingsHandler = settingsManager
        appDelegate.shortcutManager = keyboardShortcutManager
        appDelegate.fallbackPersistenceSave = dependencies.fallbackPersistenceSave

        browserManager.sumiSettings = settingsManager
        browserManager.keyboardShortcutManager = keyboardShortcutManager
        browserManager.windowShellContentViewFactory = dependencies.windowShellContentViewFactory

        let mouseCommandRouter = BrowserMouseCommandRouter(
            commandPalette: { [weak browserManager] in
                browserManager?.urlBarBundle.commandPalettePresentation
            },
            history: { [weak browserManager] in
                browserManager?.historyBundle.historyNavigationOwner
            }
        )
        let windowSession = browserManager.windowSessionBundle
        let externalURLTabOpening = ExternalURLTabOpeningService(
            windowRegistry: windowRegistry,
            tabOpening: browserManager.tabOpening
        )
        let terminationCoordinator = BrowserTerminationCoordinator(
            browserRuntime: browserManager
        )
        self.mouseCommandRouter = mouseCommandRouter
        self.externalURLTabOpening = externalURLTabOpening

        appDelegate.mouseButtonRouter = mouseCommandRouter
        appDelegate.externalURLHandler = externalURLTabOpening
        appDelegate.terminationCoordinator = terminationCoordinator

        nowPlayingController.setFeatureEnabled(settingsManager.sidebarMiniPlayerEnabled)
        nowPlayingController.configure(
            context: BrowserManagerRuntimeWiring.nativeNowPlayingRuntimeContext(for: browserManager)
        )
        dependencies.startUpdater()
        keyboardShortcutManager.attach(
            actionRouter: browserManager.shortcutActionRouter,
            targetResolver: browserManager.shortcutTargetResolver
        )

        let windowCloseWorkflow = BrowserWindowCloseWorkflow(
            browserRuntime: browserManager,
            recorder: windowSession.history.recorder,
            persistence: browserManager.windowSessionPersistenceCoordinator,
            extensions: browserManager.optionalModules.extensions,
            webViews: dependencies.webViewLifecycle,
            emptySplitPlaceholders: browserManager.splitEmptyPlaceholders,
            splitPreviews: browserManager.splitPreviews,
            commands: browserManager.windowCommands
        )
        let allWindowsClosedWorkflow = BrowserAllWindowsClosedWorkflow(
            browserRuntime: browserManager,
            sessionRestore: windowSession.restoreService,
            siteDataPolicy: browserManager.dataServices.siteDataPolicyEnforcementService,
            profiles: browserManager.profileManager
        )
        let eventSinkReceipt = BrowserWindowRegistryBinding.install(
            registration: windowSession.restoration,
            closing: windowCloseWorkflow,
            activity: browserManager.windowActivation,
            allWindowsClosed: allWindowsClosedWorkflow,
            on: windowRegistry
        )
        precondition(
            eventSinkReceipt.map(windowRegistry.validatesEventSinkInstallation)
                == true,
            "WindowRegistry event sink preflight and installation must be atomic on MainActor"
        )
        windowRegistryEventSinkReceipt = eventSinkReceipt

        let automaticPermissionCleanup = browserManager.privacyBundle
            .automaticPermissionCleanup
        let currentProfile = browserManager.currentProfile
        Task { @MainActor [automaticPermissionCleanup, currentProfile] in
            await automaticPermissionCleanup.runIfNeeded(for: currentProfile)
        }

        return true
    }

    func handleApplicationWillResignActive() {
        browserManager?.permissionRuntime
            .pauseGeolocationOnAppBackgroundIfNeeded()
    }

    func handleApplicationDidBecomeActive() {
        browserManager?.permissionRuntime
            .resumeGeolocationOnAppForegroundIfNeeded()
    }

    func handleApplicationReopen(hasVisibleWindows: Bool) -> Bool {
        let shouldCreate = BrowserApplicationReopenPolicy
            .shouldCreateNewWindow(
                hasVisibleWindows: hasVisibleWindows,
                hasOpenBrowserWindows:
                    windowRegistry?.allWindows.isEmpty == false
            )
        guard shouldCreate else { return true }
        _ = browserManager?.windowCommands.createNewWindow()
        return false
    }
}
