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
        let windowShellContentViewFactory: BrowserManager.WindowShellContentViewFactory
        let fallbackPersistenceSave: @MainActor () throws -> Void
        let startUpdater: @MainActor () -> Void
    }

    private var didSetup = false

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
        appDelegate.commandRouter = browserManager
        appDelegate.windowRouter = browserManager
        appDelegate.webViewLookup = browserManager
        appDelegate.externalURLHandler = browserManager
        appDelegate.persistenceHandler = browserManager
        appDelegate.updateHandler = browserManager
        appDelegate.appLifecycleHandler = browserManager
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
        nowPlayingController.configure(browserManager: browserManager)
        browserManager.tabManager.sumiSettings = settingsManager

        dependencies.startUpdater()
        keyboardShortcutManager.setBrowserManager(browserManager)

        windowRegistry.onWindowRegister = { [weak browserManager] windowState in
            browserManager?.setupWindowState(windowState)
        }

        for windowState in windowRegistry.allWindows {
            browserManager.setupWindowState(windowState)
        }

        windowRegistry.onWindowClose = { [webViewCoordinator, weak browserManager] windowId in
            if let browserManager {
                browserManager.handleWindowWillClose(windowId)
                browserManager.extensionsModule.notifyWindowClosedIfLoaded(windowId)
                webViewCoordinator.cleanupWindow(
                    windowId,
                    tabManager: browserManager.tabManager
                )
                browserManager.splitManager.cleanupWindow(windowId)
                browserManager.backgroundMediaOptimizationService.scheduleReconcile(
                    reason: "window-closed"
                )

                if let windowState = browserManager.windowRegistry?.windows[windowId],
                   windowState.isIncognito {
                    Task {
                        await browserManager.closeIncognitoWindow(windowState)
                    }
                }
            } else {
                webViewCoordinator.removeCompositorContainerView(for: windowId)
                RuntimeDiagnostics.emit(
                    "⚠️ [SumiApp] Window \(windowId) closed after BrowserManager deallocation - performed minimal cleanup"
                )
            }
        }

        windowRegistry.onActiveWindowChange = { [weak browserManager] windowState in
            browserManager?.setActiveWindowState(windowState)
        }

        windowRegistry.onWindowVisibilityChange = { [weak browserManager] windowState in
            browserManager?.handleWindowVisibilityChanged(windowState)
        }

        windowRegistry.onAllWindowsClosed = { [weak browserManager] in
            browserManager?.windowSessionService.prepareForAllWindowsClosed()
            Task { @MainActor [weak browserManager] in
                await browserManager?.performSiteDataPolicyAllWindowsClosedCleanup()
            }
        }

        Task { @MainActor [browserManager] in
            await browserManager.runAutomaticPermissionCleanupIfNeeded(
                for: browserManager.currentProfile
            )
        }

        return true
    }
}
