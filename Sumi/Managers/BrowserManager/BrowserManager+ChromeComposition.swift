import Foundation

@MainActor
extension BrowserManager {
    func composeChromeBundle() -> BrowserChromeBundle {
        let shell = shellRuntime
        let webViews = webViewRoutingService
        let notifications = notificationPresenter
        let clipboard = BrowserURLClipboardService(
            notifications: { [notifications] in notifications }
        )
        let activePageCommands = ActivePageCommandService(
            resolver: shell.activePageResolver,
            reloadSelectedPage: { [webViews] tab, window, reason in
                webViews.refreshPage(
                    for: tab,
                    in: window,
                    reason: reason
                )
            },
            reloadPreviewPage: { tab in
                tab.navigationCommandOwner.refresh(tab)
            },
            clipboard: clipboard,
            inspector: WebInspectorService()
        )
        let sidebarPresentation = BrowserSidebarPresentationOwner(
            windows: windowRegistry,
            persistence: windowSessionPersistenceCoordinator
        )
        let sharing = BrowserSharingPickerPresentationOwner(
            windows: windowRegistry
        )
        let nativeSurfaces = BrowserNativeSurfaceRoutingOwner(
            residence: BrowserNativeSurfaceResidenceOwner(
                ephemeralLifecycle: ephemeralLifecycleOwner,
                spaces: spaceStateOwner,
                regularTabs: regularTabCollectionOwner,
                persistence: structuralPersistence
            ),
            settings: settingsState,
            tabOpening: tabOpening,
            selection: browserTabSelection,
            windows: windowRegistry
        )
        let zoom = BrowserZoomCommandOwner(
            windows: windowRegistry,
            targets: BrowserZoomTargetResolver(
                activePages: shell.activePageResolver,
                tabs: tabCollectionMembershipOwner,
                windowTabs: shell.windowTabs,
                webViews: webViews
            ),
            policy: BrowserZoomPolicy(
                manager: zoomManager,
                boosts: optionalModules.boosts
            ),
            publication: BrowserZoomPublication(
                revision: zoomRevisionState,
                notifications: notifications
            )
        )
        let downloadsPresenter = DownloadsPopoverPresenter(
            sidebarRecoveryCoordinator: sidebarHostRecoveryCoordinator
        )
        let urlBarHubPresenter = URLBarHubPopoverPresenter(
            sidebarRecoveryCoordinator: sidebarHostRecoveryCoordinator
        )
        let commands = BrowserChromeCommands(
            windows: windowRegistry,
            downloads: downloadManager,
            privacy: BrowserPagePrivacyCommandOwner(
                activePages: shell.activePageResolver,
                windows: windowRegistry,
                dataServices: dataServices,
                profiles: currentProfileAuthority,
                webViews: webViews
            ),
            downloadsPopoverPresenter: downloadsPresenter,
            urlBarHubPopoverPresenter: urlBarHubPresenter
        )
        let nativeDialogs = BrowserNativeDialogPresentationOwner(
            modal: nativeModalTransaction,
            floatingBar: floatingBarPresentation,
            themes: workspaceThemeEditorOwner,
            sharing: sharing
        )
        return BrowserChromeBundle(
            commands: commands,
            activePageCommands: activePageCommands,
            sidebarActionOwner: BrowserSidebarActionOwner(
                spaces: spaceStateOwner,
                folderCommands: sidebarFolderCommands,
                liveFolderManager: liveFolderManager,
                settings: settingsState
            ),
            sidebarPresentationOwner: sidebarPresentation,
            workspaceThemeTransitionOwner: workspaceThemeTransitionOwner,
            workspaceThemeEditorOwner: workspaceThemeEditorOwner,
            nativeSurfaceRoutingOwner: nativeSurfaces,
            zoomCommandOwner: zoom,
            sharingPickerPresentationOwner: sharing,
            nativeDialogPresentationOwner: nativeDialogs
        )
    }
}
