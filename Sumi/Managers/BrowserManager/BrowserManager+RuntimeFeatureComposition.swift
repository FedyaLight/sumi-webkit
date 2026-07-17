import Foundation

@MainActor
extension BrowserManager {
    func composeAuxiliaryWindows() -> BrowserAuxiliaryWindowComposition {
        BrowserAuxiliaryWindowCompositionFactory.make(
            windows: windowRegistry,
            currentProfile: currentProfileAuthority,
            spaces: spaceStateOwner,
            tabContext: shellRuntime.windowTabs,
            auxiliaryTabs: auxiliaryMiniWindowTabs,
            untrackedWebViewInstallation: webViewRuntime
                .untrackedWebViewInstallationService,
            extensions: optionalModules.extensions,
            popupPermissions: permissionRuntime.popupPermissionBridge,
            filePickerPermissions: permissionRuntime.filePickerPermissionBridge,
            mutationAdmission: webViewRuntime.websiteDataCleanupService,
            profileAdmissions: profileManager.profileReferenceAdmission,
            teardownRegistry: auxiliaryWindowTeardownRegistry
        )
    }

    func composeWindowStateReconciler() -> BrowserWindowStateReconciler {
        let shell = shellRuntime
        return BrowserWindowStateReconciler(
            windows: windowRegistry,
            spaceContext: windowSpaceContextSynchronizer,
            selectionRepair: BrowserWindowSelectionRepairService(
                membership: tabCollectionMembershipOwner,
                spaces: spaceStateOwner,
                tabStore: runtimeStore,
                selection: shell.windowSelection,
                selectionOwner: browserTabSelection
            ),
            publication: BrowserWindowStateRepairPublication(
                persistence: windowSessionPersistenceCoordinator,
                visuals: shell.windowVisuals
            ),
            workspaceThemes: workspaceThemeTransitionOwner
        )
    }

    func composeWebViewCloseRouter() -> BrowserWebViewCloseRouter {
        let webViews = webViewRuntime
        let shell = shellRuntime
        let windows = windowRegistry
        let targetResolver = WebKitCloseTargetResolver(
            lifecycle: webViews.lifecycleService,
            ownership: webViews.ownershipQuery,
            membership: tabCollectionMembershipOwner,
            residences: tabResidenceAuthority,
            windowTabs: shell.windowTabs,
            routing: webViewRoutingService,
            registry: { [windows] in windows }
        )
        let childWindows = WebKitChildWindowCloseTransaction(
            lifecycle: webViews.lifecycleService,
            ownership: webViews.ownershipQuery,
            tabClosure: tabClosureService,
            windowTabs: shell.windowTabs,
            windowCommands: windowCommands,
            registry: { [windows] in windows }
        )
        let normalClose = BrowserTabWebKitCloseService(
            targets: targetResolver,
            childWindows: childWindows,
            commands: BrowserWebKitCloseCommands(
                lifecycle: webViews.lifecycleService,
                tabClose: tabCloseOrchestration,
                tabClosure: tabClosureService
            )
        )
        return BrowserWebViewCloseRouter(
            glance: glanceManager,
            auxiliaryWindows: auxiliaryWindows,
            auxiliaryTabs: auxiliaryMiniWindowTabs,
            extensions: optionalModules.extensions,
            normalClose: normalClose
        )
    }
}
