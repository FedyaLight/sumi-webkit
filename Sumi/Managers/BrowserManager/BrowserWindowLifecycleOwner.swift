import Foundation

@MainActor
final class BrowserWindowLifecycleOwner {
    struct Dependencies {
        let windowRegistry: WindowRegistry
        let browserRuntimeIsAvailable: @MainActor () -> Bool
        let setupWindowState: @MainActor (BrowserWindowState) -> Void
        let handleWindowWillClose: @MainActor (UUID) -> Void
        let notifyWindowClosedIfLoaded: @MainActor (UUID) -> Void
        let cleanupWebViews: @MainActor (UUID) -> Void
        let cleanupSplitWindow: @MainActor (UUID) -> Void
        let scheduleWindowClosedMediaReconcile: @MainActor () -> Void
        let windowState: @MainActor (UUID) -> BrowserWindowState?
        let closeIncognitoWindow: @MainActor (BrowserWindowState) async -> Void
        let setActiveWindowState: @MainActor (BrowserWindowState) -> Void
        let handleWindowVisibilityChanged: @MainActor (BrowserWindowState) -> Void
        let prepareForAllWindowsClosed: @MainActor () -> Void
        let performSiteDataPolicyAllWindowsClosedCleanup: @MainActor () async -> Void
        let cleanupWindowAfterBrowserRuntimeDeallocation: @MainActor (UUID) -> Void
    }

    private var didAttach = false

    @discardableResult
    func attachIfNeeded(dependencies: Dependencies) -> Bool {
        guard didAttach == false else { return false }
        didAttach = true

        let windowRegistry = dependencies.windowRegistry
        let browserRuntimeIsAvailable = dependencies.browserRuntimeIsAvailable
        let setupWindowState = dependencies.setupWindowState
        let handleWindowWillClose = dependencies.handleWindowWillClose
        let notifyWindowClosedIfLoaded = dependencies.notifyWindowClosedIfLoaded
        let cleanupWebViews = dependencies.cleanupWebViews
        let cleanupSplitWindow = dependencies.cleanupSplitWindow
        let scheduleWindowClosedMediaReconcile = dependencies.scheduleWindowClosedMediaReconcile
        let windowState = dependencies.windowState
        let closeIncognitoWindow = dependencies.closeIncognitoWindow
        let setActiveWindowState = dependencies.setActiveWindowState
        let handleWindowVisibilityChanged = dependencies.handleWindowVisibilityChanged
        let prepareForAllWindowsClosed = dependencies.prepareForAllWindowsClosed
        let performSiteDataPolicyAllWindowsClosedCleanup =
            dependencies.performSiteDataPolicyAllWindowsClosedCleanup
        let cleanupWindowAfterBrowserRuntimeDeallocation =
            dependencies.cleanupWindowAfterBrowserRuntimeDeallocation

        windowRegistry.onWindowRegister = { windowState in
            setupWindowState(windowState)
        }

        for windowState in windowRegistry.allWindows {
            setupWindowState(windowState)
        }

        windowRegistry.onWindowClose = { windowId in
            guard browserRuntimeIsAvailable() else {
                cleanupWindowAfterBrowserRuntimeDeallocation(windowId)
                return
            }

            handleWindowWillClose(windowId)
            notifyWindowClosedIfLoaded(windowId)
            cleanupWebViews(windowId)
            cleanupSplitWindow(windowId)
            scheduleWindowClosedMediaReconcile()

            if let windowState = windowState(windowId),
               windowState.isIncognito {
                Task {
                    await closeIncognitoWindow(windowState)
                }
            }
        }

        windowRegistry.onActiveWindowChange = { windowState in
            setActiveWindowState(windowState)
        }

        windowRegistry.onWindowVisibilityChange = { windowState in
            handleWindowVisibilityChanged(windowState)
        }

        windowRegistry.onAllWindowsClosed = {
            prepareForAllWindowsClosed()
            Task { @MainActor in
                await performSiteDataPolicyAllWindowsClosedCleanup()
            }
        }

        return true
    }
}

extension BrowserWindowLifecycleOwner.Dependencies {
    static func live(
        browserManager: BrowserManager,
        windowRegistry: WindowRegistry,
        webViewCoordinator: WebViewCoordinator
    ) -> Self {
        Self(
            windowRegistry: windowRegistry,
            browserRuntimeIsAvailable: { [weak browserManager] in
                browserManager != nil
            },
            setupWindowState: { [weak browserManager] windowState in
                browserManager?.setupWindowState(windowState)
            },
            handleWindowWillClose: { [weak browserManager] windowId in
                browserManager?.handleWindowWillClose(windowId)
            },
            notifyWindowClosedIfLoaded: { [weak browserManager] windowId in
                browserManager?.extensionsModule.notifyWindowClosedIfLoaded(windowId)
            },
            cleanupWebViews: { [webViewCoordinator, weak browserManager] windowId in
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
                await browserManager?.closeIncognitoWindow(windowState)
            },
            setActiveWindowState: { [weak browserManager] windowState in
                browserManager?.setActiveWindowState(windowState)
            },
            handleWindowVisibilityChanged: { [weak browserManager] windowState in
                browserManager?.handleWindowVisibilityChanged(windowState)
            },
            prepareForAllWindowsClosed: { [weak browserManager] in
                browserManager?.windowSessionService.prepareForAllWindowsClosed()
            },
            performSiteDataPolicyAllWindowsClosedCleanup: { [weak browserManager] in
                await browserManager?.performSiteDataPolicyAllWindowsClosedCleanup()
            },
            cleanupWindowAfterBrowserRuntimeDeallocation: { [webViewCoordinator] windowId in
                webViewCoordinator.removeCompositorContainerView(for: windowId)
                RuntimeDiagnostics.emit(
                    "⚠️ [SumiApp] Window \(windowId) closed after BrowserManager deallocation - performed minimal cleanup"
                )
            }
        )
    }
}
