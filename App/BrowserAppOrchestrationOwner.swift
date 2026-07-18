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

    private var applicationLifecycleController: BrowserApplicationLifecycleController?
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

        appDelegate.windowRegistry = windowRegistry
        let applicationLifecycleController = BrowserApplicationLifecycleController(
            scheduleBackgroundMediaReconcile: { [weak browserManager] reason in
                browserManager?.backgroundMediaOptimizationService.scheduleReconcile(reason: reason)
            },
            pauseGeolocationOnAppBackgroundIfNeeded: { [weak browserManager] in
                browserManager?.permissionRuntime.pauseGeolocationOnAppBackgroundIfNeeded()
            },
            resumeGeolocationOnAppForegroundIfNeeded: { [weak browserManager] in
                browserManager?.permissionRuntime.resumeGeolocationOnAppForegroundIfNeeded()
            }
        )
        self.applicationLifecycleController = applicationLifecycleController
        appDelegate.appLifecycleHandler = applicationLifecycleController
        appDelegate.settingsHandler = settingsManager
        appDelegate.shortcutManager = keyboardShortcutManager
        appDelegate.fallbackPersistenceSave = dependencies.fallbackPersistenceSave

        browserManager.sumiSettings = settingsManager
        browserManager.keyboardShortcutManager = keyboardShortcutManager
        browserManager.windowShellContentViewFactory = dependencies.windowShellContentViewFactory
        Task { [downloadManager = browserManager.downloadManager] in
            await downloadManager.performStartupMaintenance()
        }

        let mouseCommandRouter = BrowserMouseCommandRouter(
            floatingBar: { [weak browserManager] in
                browserManager?.urlBarBundle.floatingBar.presentation
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
            targetResolver: browserManager.shortcutTargetResolver,
            extensionsModule: browserManager.optionalModules.extensions
        )

        let windowCloseWorkflow = BrowserWindowCloseWorkflow(
            browserRuntime: browserManager,
            recorder: windowSession.history.recorder,
            persistence: browserManager.windowSessionPersistenceCoordinator,
            extensions: browserManager.optionalModules.extensions,
            webViews: dependencies.webViewLifecycle,
            emptySplitPlaceholders: browserManager.splitEmptyPlaceholders,
            splitPreviews: browserManager.splitPreviews,
            backgroundMedia: browserManager.backgroundMediaOptimizationService,
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
}
