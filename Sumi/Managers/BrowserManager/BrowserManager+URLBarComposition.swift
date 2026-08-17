import Foundation

@MainActor
extension BrowserManager {
    func composeURLBarBundle() -> BrowserURLBarBundle {
        let shell = shellRuntime
        let chrome = chromeBundle
        let webViews = webViewRoutingService
        let settingsNavigation = BrowserSettingsNavigationService(
            settings: { [settingsState] in settingsState.settings },
            currentTab: { [windowTabs = shell.windowTabs] window in
                windowTabs.currentTab(for: window)
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
            bookmarks: bookmarkEditorPresentationState,
            activePages: shell.activePageResolver,
            pageCommands: chrome.activePageCommands,
            webViews: webViews
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
            pages: pageProjection,
            windows: windowRegistry
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
                commandPalette: commandPalettePresentation,
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
            commandPalettePresentation: commandPalettePresentation,
            commandPaletteCommit: commandPaletteCommit,
            commandPaletteBrowserContext: commandPaletteBrowserContext
        )
    }
}
