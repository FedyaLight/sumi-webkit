import Foundation

@MainActor
final class BrowserAppOrchestrationOwner {
    struct Dependencies {
        let appDelegate: AppDelegate
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
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
    private var didSetup = false

    @discardableResult
    func setupIfNeeded(dependencies: Dependencies) -> Bool {
        guard !didSetup else { return false }
        didSetup = true

        let appDelegate = dependencies.appDelegate
        let browserManager = dependencies.browserManager
        let windowRegistry = dependencies.windowRegistry
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

        browserManager.windowRegistry = windowRegistry
        browserManager.sumiSettings = settingsManager
        browserManager.keyboardShortcutManager = keyboardShortcutManager
        browserManager.windowShellContentViewFactory = dependencies.windowShellContentViewFactory

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
            tabOpening: browserManager.tabLifecycleService.opening
        )
        let terminationCoordinator = BrowserTerminationCoordinator(
            browserRuntime: browserManager
        )
        self.mouseCommandRouter = mouseCommandRouter
        self.externalURLTabOpening = externalURLTabOpening

        appDelegate.mouseButtonRouter = mouseCommandRouter
        appDelegate.tabCommandRouter = browserManager.tabLifecycleService.closeOrchestration
        appDelegate.windowRouter = browserManager.windowCommands
        appDelegate.externalURLHandler = externalURLTabOpening
        appDelegate.terminationCoordinator = terminationCoordinator

        nowPlayingController.setFeatureEnabled(settingsManager.sidebarMiniPlayerEnabled)
        nowPlayingController.configure(
            context: BrowserManagerRuntimeWiring.nativeNowPlayingRuntimeContext(for: browserManager)
        )
        browserManager.tabManager.sumiSettings = settingsManager

        dependencies.startUpdater()
        keyboardShortcutManager.attach(
            actionRouter: browserManager.shortcutActionRouter,
            chromeRouter: browserManager.shortcutActionRouter,
            windowRegistry: windowRegistry,
            extensionCommandHandler: { [weak browserManager] event in
                browserManager?.optionalModules.extensions.performExtensionKeyboardCommandIfLoaded(for: event) ?? false
            }
        )

        let windowCloseWorkflow = BrowserWindowCloseWorkflow(
            browserRuntime: browserManager,
            recorder: windowSession.history.recorder,
            persistence: windowSession.persistence,
            extensions: browserManager.optionalModules.extensions,
            webViews: dependencies.webViewLifecycle,
            emptySplitPlaceholders: browserManager.splitComposition
                .emptyPlaceholders,
            splitPreviews: browserManager.splitComposition.previews,
            backgroundMedia: browserManager.backgroundMediaOptimizationService,
            commands: browserManager.windowCommands
        )
        let allWindowsClosedWorkflow = BrowserAllWindowsClosedWorkflow(
            browserRuntime: browserManager,
            sessionRestore: windowSession.restoreService,
            siteDataPolicy: browserManager.dataServices.siteDataPolicyEnforcementService,
            profiles: browserManager.profileManager
        )
        BrowserWindowRegistryBinding.install(
            registration: windowSession.restoration,
            closing: windowCloseWorkflow,
            activity: windowSession.activation,
            allWindowsClosed: allWindowsClosedWorkflow,
            on: windowRegistry
        )

        Task { @MainActor [browserManager] in
            await browserManager.privacyBundle.automaticDataCleanupOwner.runAutomaticPermissionCleanupIfNeeded(
                for: browserManager.currentProfile
            )
        }

        return true
    }
}
