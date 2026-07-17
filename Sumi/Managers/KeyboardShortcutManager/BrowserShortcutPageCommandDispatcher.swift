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

    func dispatch(_ action: ShortcutAction) -> Bool {
        switch action {
        case .goBack:
            history.goBackInActiveWindow()
        case .goForward:
            history.goForwardInActiveWindow()
        case .refresh:
            page.reloadActivePage()
        case .clearCookiesAndRefresh:
            privacy.clearCurrentPageCookies()
            page.reloadActivePage()
        case .openDevTools:
            page.inspectActivePage()
        case .viewHistory:
            history.openHistoryTab()
        case .zoomIn:
            zoom.zoomInCurrentTab()
        case .zoomOut:
            zoom.zoomOutCurrentTab()
        case .actualSize:
            zoom.resetZoomCurrentTab()
        case .copyCurrentURL:
            page.copyActivePageURL()
        case .hardReload:
            privacy.hardReloadCurrentPage()
        case .muteUnmuteAudio:
            page.toggleMuteForActivePage()
        default:
            return false
        }
        return true
    }
}
