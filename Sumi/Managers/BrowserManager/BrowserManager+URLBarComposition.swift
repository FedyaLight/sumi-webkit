import Foundation

@MainActor
extension BrowserManager {
    func composeURLBarBundle() -> BrowserURLBarBundle {
        let shell = shellRuntime
        let chrome = chromeBundle
        let webViews = webViewRoutingService
        let nativeSurfaces = chrome.nativeSurfaceRoutingOwner
        let settingsNavigation = BrowserSettingsNavigationService(
            activeWindow: { [windowRegistry] in
                windowRegistry.activeWindow
            },
            currentTab: { [windowTabs = shell.windowTabs] window in
                windowTabs.currentTab(for: window)
            },
            settingsSurfaceURL: { pane in
                BrowserPermissionSettingsRoutes.settingsSurfaceURL(for: pane)
            },
            siteSettingsSurfaceURL: { tab in
                BrowserPermissionSettingsRoutes
                    .privacySiteSettingsSurfaceURL(focusing: tab)
            },
            openNativeSurface: { [nativeSurfaces] kind, url, window in
                nativeSurfaces.openNativeBrowserSurface(
                    kind,
                    url: url,
                    in: window
                )
            }
        )
        let extensionActions = BrowserURLBarExtensionActionContextOwner(
            extensions: optionalModules.extensions,
            tabs: SidebarExtensionActionTabQuery(
                windowTabs: shell.windowTabs,
                membership: tabCollectionMembershipOwner,
                selection: shell.windowSelection,
                tabStore: runtimeStore
            ),
            profiles: currentProfileAuthority,
            settings: settingsNavigation
        )
        let pageProjection = BrowserURLBarPageProjectionOwner(
            profileManager: profileManager,
            currentProfile: currentProfileAuthority,
            webViews: webViews,
            extensionActions: extensionActions,
            siteControls: BrowserSiteControlsContextOwner(
                protection: protectionCoordinator,
                extensions: optionalModules.extensions
            )
        )
        let permissionContext = BrowserURLBarPermissionContextOwner(
            runtime: permissionRuntime,
            webViews: webViews
        )
        let hubCommands = BrowserURLBarHubCommandOwner(
            boosts: optionalModules.boosts,
            extensions: optionalModules.extensions,
            settings: settingsNavigation,
            sharing: chrome.sharingPickerPresentationOwner,
            bookmarks: bookmarkEditorPresentationState
        )
        let hub = BrowserURLBarHubContextOwner(
            bookmarks: bookmarkManager,
            permissions: permissionContext,
            siteData: BrowserURLBarSiteDataContextOwner(
                protection: protectionCoordinator,
                adblockZapperStore: adblockZapperStore,
                dataServices: dataServices
            ),
            commands: hubCommands,
            pages: pageProjection
        )
        let hubPresentation = BrowserURLBarHubPresentationOwner(
            presenter: chrome.commands.urlBarHubPopoverPresenter
        )
        let clipboard = BrowserURLClipboardService(
            notifications: { [notifications = notificationPresenter] in
                notifications
            }
        )
        let contextOwner = BrowserURLBarContextOwner(
            hub: hub,
            navigation: BrowserNavigationToolbarContextOwner(
                windowTabs: shell.windowTabs,
                webViews: webViews,
                dataServices: dataServices,
                history: historyBundle.historyNavigationOwner,
                tabOpening: tabOpening
            ),
            pageCommands: BrowserURLBarPageCommandOwner(
                activePages: shell.activePageResolver,
                floatingBar: floatingBarPresentation,
                pageCommands: chrome.activePageCommands,
                clipboard: clipboard,
                sidebar: chrome.sidebarPresentationOwner
            ),
            zoom: BrowserURLBarZoomContextOwner(
                manager: zoomManager,
                revision: zoomRevisionState,
                commands: chrome.zoomCommandOwner
            ),
            hubPresentation: hubPresentation
        )
        return BrowserURLBarBundle(
            settingsNavigation: settingsNavigation,
            contextOwner: contextOwner,
            floatingBar: floatingBarServices
        )
    }
}
