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
            windowRegistry: windowRegistry,
            extensionCommandHandler: { [weak browserManager] event in
                browserManager?.extensionsModule.performExtensionKeyboardCommandIfLoaded(for: event) ?? false
            }
        )

        windowLifecycleOwner.attachIfNeeded(
            windowRegistry: windowRegistry,
            browserRuntimeIsAvailable: { [weak browserManager] in
                browserManager != nil
            },
            setupWindowState: { [weak browserManager] windowState in
                browserManager?.windowSessionActivationOwner.setupWindowState(windowState)
            },
            handleWindowWillClose: { [weak browserManager] windowId in
                browserManager?.windowHistorySessionOwner.handleWindowWillClose(windowId)
            },
            notifyWindowClosedIfLoaded: { [weak browserManager] windowId in
                browserManager?.extensionsModule.notifyWindowClosedIfLoaded(windowId)
            },
            cleanupWebViews: { [weak browserManager] windowId in
                guard let browserManager else { return }
                webViewCoordinator.cleanupWindow(
                    windowId,
                    tabManager: browserManager.tabManager
                )
            },
            cleanupSplitWindow: { [weak browserManager] windowId in
                browserManager?.splitManager.cleanupWindow(windowId)
            },
            scheduleWindowClosedMediaReconcile: { [weak browserManager] in
                browserManager?.backgroundMediaOptimizationService.scheduleReconcile(
                    reason: "window-closed"
                )
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            closeIncognitoWindow: { [weak browserManager] windowState in
                await browserManager?.windowSessionCommands.closeIncognitoWindow(windowState)
            },
            setActiveWindowState: { [weak browserManager] windowState in
                browserManager?.windowSessionActivationOwner.setActiveWindowState(windowState)
            },
            handleWindowVisibilityChanged: { [weak browserManager] windowState in
                browserManager?.windowSessionActivationOwner.handleWindowVisibilityChanged(windowState)
            },
            prepareForAllWindowsClosed: { [weak browserManager] in
                browserManager?.windowSessionService.prepareForAllWindowsClosed()
            },
            performAllWindowsClosedSiteDataCleanup: { [weak browserManager] in
                guard let browserManager else { return }
                await browserManager.dataServices.siteDataPolicyEnforcementService
                    .performAllWindowsClosedCleanup(
                        profiles: browserManager.profileManager.profiles
                    )
            },
            cleanupWindowAfterRuntimeDeallocation: { windowId in
                webViewCoordinator.removeCompositorContainerView(for: windowId)
                RuntimeDiagnostics.emit(
                    "⚠️ [SumiApp] Window \(windowId) closed after BrowserManager deallocation - performed minimal cleanup"
                )
            }
        )

        Task { @MainActor [browserManager] in
            await browserManager.automaticDataCleanupOwner.runAutomaticPermissionCleanupIfNeeded(
                for: browserManager.currentProfile
            )
        }

        return true
    }
}
