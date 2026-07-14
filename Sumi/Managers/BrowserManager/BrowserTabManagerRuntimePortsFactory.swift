import Foundation

@MainActor
enum BrowserTabManagerRuntimePortsFactory {
    static func registry(for browserManager: BrowserManager) -> RuntimePortRegistry {
        let webViewRuntime = browserManager.webViewRuntime
        return RuntimePortRegistry(
            profileQuery: LiveTabProfileQueryPort(
                currentProfileAuthority: browserManager.currentProfileAuthority,
                profileManager: browserManager.profileManager,
                settingsAttachment: browserManager.settingsAttachment
            ),
            windowQuery: LiveTabWindowQueryPort(
                shellRuntime: browserManager.shellRuntime,
                compositor: browserManager.compositorManager,
                windowStateReconciler: browserManager.windowStateReconciler,
                persistence: browserManager.windowSessionBundle.persistence,
                workspaceThemes: browserManager.chromeBundle.workspaceThemeTransitionOwner
            ),
            splitCoordination: LiveTabSplitCoordinationPort(
                tabClosures: browserManager.splitComposition.tabClosures,
                query: browserManager.splitComposition.query
            ),
            extensionLifecycle: LiveTabExtensionLifecyclePort(
                extensions: browserManager.optionalModules.extensions.runtimeSurface
            ),
            sessionSideEffects: LiveTabSessionSideEffectsPort(
                recentlyClosedManager: browserManager.recentlyClosedManager,
                notificationPresenter: browserManager.notificationPresenter,
                webViewCloseRouter: browserManager.webViewCloseRouter,
                liveFolderManager: browserManager.liveFolderManager
            ),
            webViewLifecycle: BrowserTabManagerWebViewLifecycleFactory.service(
                webViewLifecycle: webViewRuntime.lifecycleService,
                ownershipQuery: webViewRuntime.ownershipQuery,
                trackedAdmission: webViewRuntime.trackedWebViewAdmission,
                rebuild: webViewRuntime.rebuildService,
                profileAssignment: webViewRuntime.profileAssignmentService,
                compositor: browserManager.compositorManager,
                webViewRouting: browserManager.webViewRoutingService,
                tabBrowserRuntime: TabBrowserRuntimeFactory.make(for: browserManager)
            )
        )
    }
}
