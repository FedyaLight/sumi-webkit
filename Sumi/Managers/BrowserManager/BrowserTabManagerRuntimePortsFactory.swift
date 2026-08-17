import Foundation

@MainActor
enum BrowserTabManagerRuntimePortsFactory {
    static func registry(
        for browserManager: BrowserManager,
        splitQuery: WindowSplitQuery
    ) -> RuntimePortRegistry {
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
                persistence: browserManager.windowSessionPersistenceCoordinator,
                workspaceThemes: browserManager.chromeBundle.workspaceThemeTransitionOwner
            ),
            splitCoordination: LiveTabSplitCoordinationPort(
                tabClosures: browserManager.splitTabClosures,
                query: splitQuery
            ),
            extensionLifecycle: LiveTabExtensionLifecyclePort(
                extensions: browserManager.optionalModules.extensions.runtimeSurface
            ),
            sessionSideEffects: LiveTabSessionSideEffectsPort(
                recentlyClosedManager: browserManager.recentlyClosedManager,
                notificationPresenter: browserManager.notificationPresenter,
                webViewCloseRouter: browserManager.webViewCloseRouter,
                folders: browserManager.folderCollectionStateOwner,
                liveFolderManager: browserManager.liveFolderManager
            ),
            webViewLifecycle: BrowserTabManagerWebViewLifecycleFactory.service(
                webViewLifecycle: webViewRuntime.lifecycleService,
                webViewProtection: webViewRuntime.protectionRuntime,
                committedRetirement: WebViewCommittedTabRetirementService(
                    runtimeTabs: webViewRuntime.runtimeTabs,
                    generations: webViewRuntime.retiredGenerationDestroyer
                ),
                ownershipQuery: webViewRuntime.ownershipQuery,
                trackedAdmission: webViewRuntime.trackedWebViewAdmission,
                rebuild: webViewRuntime.rebuildService,
                profileAssignment: webViewRuntime.profileAssignmentService,
                compositor: browserManager.compositorManager,
                webViewRouting: browserManager.webViewRoutingService,
                tabBrowserRuntime: browserManager.tabBrowserRuntimeReference,
                startupProtection: browserManager.startupProtectionRuntime
            )
        )
    }
}
