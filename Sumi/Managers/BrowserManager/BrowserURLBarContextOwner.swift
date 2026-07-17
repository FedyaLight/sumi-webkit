import SumiDomain

@MainActor
final class BrowserURLBarContextOwner {
    private let hub: BrowserURLBarHubContextOwner
    private let navigation: BrowserNavigationToolbarContextOwner
    private let pageCommands: BrowserURLBarPageCommandOwner
    private let zoom: BrowserURLBarZoomContextOwner
    private let hubPresentation: BrowserURLBarHubPresentationOwner

    init(
        hub: BrowserURLBarHubContextOwner,
        navigation: BrowserNavigationToolbarContextOwner,
        pageCommands: BrowserURLBarPageCommandOwner,
        zoom: BrowserURLBarZoomContextOwner,
        hubPresentation: BrowserURLBarHubPresentationOwner
    ) {
        self.hub = hub
        self.navigation = navigation
        self.pageCommands = pageCommands
        self.zoom = zoom
        self.hubPresentation = hubPresentation
    }

    func sidebarHeaderContext(
        for windowState: BrowserWindowState
    ) -> SidebarHeaderBrowserContext {
        SidebarHeaderBrowserContext(
            navigationToolbarContext: navigationToolbarContext(for: windowState),
            urlBarBrowserContext: urlBarContext,
            toggleSidebar: { [pageCommands, weak windowState] in
                guard let windowState else { return }
                pageCommands.toggleSidebar(in: windowState)
            }
        )
    }

    var urlBarContext: URLBarBrowserContext {
        URLBarBrowserContext(
            zoom: zoom.context,
            permission: hub.permissionContext,
            hub: hub.context,
            hubPopoverPresenter: hubPresentation.presenter,
            bookmarkEditorPresentationRequest: hub.bookmarkPresentationRequest,
            activePage: { [pageCommands] windowState in
                pageCommands.activePage(in: windowState)
            },
            webView: { [hub] tab, windowState in
                hub.webView(for: tab, in: windowState)
            },
            profiles: { [hub] in hub.profiles },
            currentProfile: { [hub] in hub.currentProfile },
            siteControlsSnapshot: { [hub] url, profile, protectionReload, blockerReload in
                hub.siteControlsSnapshot(
                    url: url,
                    profile: profile,
                    protectionReloadRequired: protectionReload,
                    contentBlockerReloadRequired: blockerReload
                )
            },
            focusFloatingBar: { [pageCommands] windowState, prefill, navigateCurrentTab in
                pageCommands.focusFloatingBar(
                    in: windowState,
                    prefill: prefill,
                    navigateCurrentTab: navigateCurrentTab
                )
            },
            reloadPage: { [pageCommands] page, reason in
                pageCommands.reload(page, reason: reason)
            },
            closeURLBarHubPopover: { [hubPresentation] windowState in
                hubPresentation.close(in: windowState)
            },
            presentURLBarHubPopover: { [hub, hubPresentation] windowState in
                hubPresentation.present(in: windowState, context: hub.context)
            },
            toggleURLBarHubPopover: { [hub, hubPresentation] windowState in
                hubPresentation.toggle(in: windowState, context: hub.context)
            },
            isURLBarHubPopoverPresented: { [hubPresentation] windowState in
                hubPresentation.isPresented(in: windowState)
            },
            copyURLToClipboard: { [pageCommands] urlString, windowState in
                pageCommands.copyURL(urlString, in: windowState)
            },
            extensionActions: hub.extensionActionContext
        )
    }

    var urlBarHubContext: URLBarHubBrowserContext {
        hub.context
    }

    func navigationToolbarContext(
        for windowState: BrowserWindowState
    ) -> NavigationToolbarBrowserContext {
        navigation.navigationToolbarContext(for: windowState)
    }

    func navigationHistoryContext(
        for windowState: BrowserWindowState
    ) -> SumiNavigationHistoryContext {
        navigation.navigationHistoryContext(for: windowState)
    }
}
