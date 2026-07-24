import SumiDomain

@MainActor
final class BrowserShortcutPageCommandDispatcher {
    private let history: BrowserHistoryNavigationOwner
    private let page: ActivePageCommandService
    private let pageActions: URLBarHubPageActionOwner
    private let boosts: SumiBoostsModule
    private let zoom: BrowserZoomCommandOwner
    private let privacy: BrowserChromeCommands

    init(
        history: BrowserHistoryNavigationOwner,
        page: ActivePageCommandService,
        pageActions: URLBarHubPageActionOwner,
        boosts: SumiBoostsModule,
        zoom: BrowserZoomCommandOwner,
        privacy: BrowserChromeCommands
    ) {
        self.history = history
        self.page = page
        self.pageActions = pageActions
        self.boosts = boosts
        self.zoom = zoom
        self.privacy = privacy
    }

    func dispatch(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> Bool {
        switch action {
        case .goBack:
            history.goBack(in: context.windowState)
        case .goForward:
            history.goForward(in: context.windowState)
        case .refresh:
            guard let activePage = context.page else { return false }
            return page.reload(
                activePage,
                reason: "Shortcut.refresh"
            ) != .failed
        case .clearCookiesAndRefresh:
            guard let activePage = context.page else { return false }
            privacy.clearCookies(for: context.page)
            return page.reload(
                activePage,
                reason: "Shortcut.clearCookiesAndRefresh"
            ) != .failed
        case .openDevTools:
            return page.inspect(context.page)
        case .viewHistory:
            history.openHistoryTab(in: context.windowState)
        case .zoomIn:
            zoom.zoomInCurrentTab(in: context.windowState)
        case .zoomOut:
            zoom.zoomOutCurrentTab(in: context.windowState)
        case .actualSize:
            zoom.resetZoomCurrentTab(in: context.windowState)
        case .copyCurrentURL:
            return page.copyURL(context.page)
        case .hardReload:
            privacy.hardReload(context.page)
        case .muteUnmuteAudio:
            page.toggleMute(context.page)
        case .printPage:
            return page.printPage(context.page)
        case .captureScreenshot:
            return pageActions.captureUsingSavedSettings(context.page)
        case .newBoost:
            guard let target = context.page else { return false }
            DispatchQueue.main.async { [boosts] in
                do {
                    try boosts.createBoostAndOpenEditor(
                        tab: target.tab,
                        profile: target.tab.resolveProfile(),
                        windowState: context.windowState
                    )
                } catch {
                    RuntimeDiagnostics.debug(
                        "Command palette Boost creation failed: \(error)",
                        category: "CommandPalette"
                    )
                }
            }
        default:
            return false
        }
        return true
    }

    func canDispatch(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> Bool {
        return switch action {
        case .viewHistory:
            true
        case .goBack:
            context.page?.presentationWebView?.canGoBack == true
        case .goForward:
            context.page?.presentationWebView?.canGoForward == true
        case .refresh, .clearCookiesAndRefresh, .hardReload,
             .muteUnmuteAudio:
            page.canUseWebPage(context.page)
        case .openDevTools:
            page.canInspect(context.page)
        case .copyCurrentURL:
            page.canCopyURL(context.page)
        case .printPage:
            page.canPrint(context.page)
        case .zoomIn, .zoomOut, .actualSize:
            zoom.canZoomCurrentTab(in: context.windowState)
        case .captureScreenshot:
            pageActions.canCapture(context.page)
        case .newBoost:
            context.page?.source == .selectedTab
                && boosts.canBoost(url: context.page?.url)
        default:
            false
        }
    }
}
