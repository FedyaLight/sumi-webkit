import Foundation

@MainActor
final class BrowserAppOrchestrationOwner {
    struct Dependencies {
        let appDelegate: AppDelegate
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let webViewCoordinator: WebViewCoordinator
        let settingsManager: SumiSettingsService
        let keyboardShortcutManager: KeyboardShortcutManager
        let nowPlayingController: SumiNativeNowPlayingController
        let windowShellContentViewFactory: BrowserWindowShellService.ContentViewFactory
        let fallbackPersistenceSave: @MainActor () throws -> Void
        let startUpdater: @MainActor () -> Void
    }

    private let windowLifecycleOwner: BrowserWindowLifecycleOwner
    private var applicationLifecycleController: BrowserApplicationLifecycleController?
    private var didSetup = false

    init(windowLifecycleOwner: BrowserWindowLifecycleOwner = BrowserWindowLifecycleOwner()) {
        self.windowLifecycleOwner = windowLifecycleOwner
    }

    @discardableResult
    func setupIfNeeded(dependencies: Dependencies) -> Bool {
        guard !didSetup else { return false }
        didSetup = true

        let appDelegate = dependencies.appDelegate
        let browserManager = dependencies.browserManager
        let windowRegistry = dependencies.windowRegistry
        let webViewCoordinator = dependencies.webViewCoordinator
        let settingsManager = dependencies.settingsManager
        let keyboardShortcutManager = dependencies.keyboardShortcutManager
        let nowPlayingController = dependencies.nowPlayingController

        appDelegate.windowRegistry = windowRegistry
        appDelegate.mouseButtonRouter = browserManager.appCommandRouter
        appDelegate.tabCommandRouter = browserManager.appCommandRouter
        appDelegate.windowRouter = browserManager.appCommandRouter
        appDelegate.externalURLHandler = browserManager.appCommandRouter
        appDelegate.persistenceHandler = browserManager.appCommandRouter
        appDelegate.terminationHandler = browserManager.appCommandRouter
        let applicationLifecycleController = BrowserApplicationLifecycleController(
            dependencies: .live(browserManager: browserManager)
        )
        self.applicationLifecycleController = applicationLifecycleController
        appDelegate.appLifecycleHandler = applicationLifecycleController
        appDelegate.settingsHandler = settingsManager
        appDelegate.shortcutManager = keyboardShortcutManager
        appDelegate.fallbackPersistenceSave = dependencies.fallbackPersistenceSave

        // Required before any routing or cleanup path calls BrowserManager.requireWebViewCoordinator().
        browserManager.webViewCoordinator = webViewCoordinator
        browserManager.windowRegistry = windowRegistry
        browserManager.sumiSettings = settingsManager
        browserManager.keyboardShortcutManager = keyboardShortcutManager
        browserManager.windowShellContentViewFactory = dependencies.windowShellContentViewFactory

        nowPlayingController.setFeatureEnabled(settingsManager.sidebarMiniPlayerEnabled)
        nowPlayingController.configure(
            context: BrowserManagerRuntimeWiring.nativeNowPlayingRuntimeContext(for: browserManager)
        )
        browserManager.tabManager.sumiSettings = settingsManager

        dependencies.startUpdater()
        keyboardShortcutManager.attach(
            actionRouter: browserManager.shortcutActionRouter,
            chromeRouter: browserManager.shortcutActionRouter,
            windowRegistry: windowRegistry
        )

        windowLifecycleOwner.attachIfNeeded(
            dependencies: .live(
                browserManager: browserManager,
                windowRegistry: windowRegistry,
                webViewCoordinator: webViewCoordinator
            )
        )

        Task { @MainActor [browserManager] in
            await browserManager.automaticDataCleanupOwner.runAutomaticPermissionCleanupIfNeeded(
                for: browserManager.currentProfile
            )
        }

        return true
    }
}
