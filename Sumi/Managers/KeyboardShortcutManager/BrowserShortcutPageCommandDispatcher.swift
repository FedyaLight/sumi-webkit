import SumiDomain

@MainActor
final class BrowserShortcutPageCommandDispatcher {
    private let history: BrowserHistoryNavigationOwner
    private let page: ActivePageCommandService
    private let zoom: BrowserZoomCommandOwner
    private let privacy: BrowserChromeCommands

    init(
        history: BrowserHistoryNavigationOwner,
        page: ActivePageCommandService,
        zoom: BrowserZoomCommandOwner,
        privacy: BrowserChromeCommands
    ) {
        self.history = history
        self.page = page
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
            if let activePage = context.page {
                _ = page.reload(activePage, reason: "Shortcut.refresh")
            }
        case .clearCookiesAndRefresh:
            privacy.clearCookies(for: context.page)
            if let activePage = context.page {
                _ = page.reload(
                    activePage,
                    reason: "Shortcut.clearCookiesAndRefresh"
                )
            }
        case .openDevTools:
            page.inspect(context.page)
        case .viewHistory:
            history.openHistoryTab(in: context.windowState)
        case .zoomIn:
            zoom.zoomInCurrentTab(in: context.windowState)
        case .zoomOut:
            zoom.zoomOutCurrentTab(in: context.windowState)
        case .actualSize:
            zoom.resetZoomCurrentTab(in: context.windowState)
        case .copyCurrentURL:
            page.copyURL(context.page)
        case .hardReload:
            privacy.hardReload(context.page)
        case .muteUnmuteAudio:
            page.toggleMute(context.page)
        default:
            return false
        }
        return true
    }
}
