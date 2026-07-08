import WebKit

@MainActor
final class BrowserWebViewRoutingService {
    typealias TabLookup = @MainActor (UUID) -> Tab?
    typealias WebViewCoordinatorProvider = @MainActor () -> WebViewCoordinator

    private let tabLookup: TabLookup
    private let coordinatorProvider: WebViewCoordinatorProvider

    init(
        tabLookup: @escaping TabLookup,
        coordinatorProvider: @escaping WebViewCoordinatorProvider
    ) {
        self.tabLookup = tabLookup
        self.coordinatorProvider = coordinatorProvider
    }

    func webView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        coordinatorProvider().getWebView(for: tabId, in: windowId)
    }

    func windowOwnedWebView(for tab: Tab, in windowId: UUID) -> WKWebView? {
        webView(for: tab.id, in: windowId)
    }

    @discardableResult
    func getOrCreateWebView(for tab: Tab, in windowId: UUID) -> WKWebView? {
        coordinatorProvider().getOrCreateWebView(for: tab, in: windowId)
    }

    /// Live WebViews known to the coordinator registry for this tab.
    func trackedWebViews(for tabId: UUID) -> [WKWebView] {
        coordinatorProvider().getAllWebViews(for: tabId)
    }

    /// Prefer a window-tracked WebView; fall back to an untracked tab-owned instance
    /// (popup / pre-window / Glance materialization) via the coordinator.
    func anyLiveWebView(for tab: Tab) -> WKWebView? {
        coordinatorProvider().anyLiveWebView(for: tab)
    }

    func ownsLiveWebView(_ webView: WKWebView, for tab: Tab) -> Bool {
        coordinatorProvider().ownsLiveWebView(webView, for: tab)
    }

    func hasLiveWebView(for tab: Tab) -> Bool {
        coordinatorProvider().hasLiveWebView(for: tab)
    }

    func hasUntrackedOwnedWebView(for tab: Tab) -> Bool {
        coordinatorProvider().untrackedOwnedWebView(for: tab) != nil
    }

    func assignWebView(_ webView: WKWebView, to tab: Tab, in windowId: UUID) {
        coordinatorProvider().assignWebView(webView, to: tab, in: windowId)
    }

    func installUntrackedOwnedWebView(_ webView: WKWebView, for tab: Tab) {
        coordinatorProvider().installUntrackedOwnedWebView(webView, for: tab)
    }

    @discardableResult
    func ensureUntrackedOwnedWebView(for tab: Tab) -> WKWebView? {
        coordinatorProvider().ensureUntrackedOwnedWebView(for: tab)
    }

    func releaseUntrackedOwnedWebView(for tab: Tab) {
        coordinatorProvider().releaseUntrackedOwnedWebView(for: tab)
    }

    @discardableResult
    func replaceLiveWebView(
        for tab: Tab,
        in windowId: UUID?,
        reason: String,
        prepareConfiguration: ((WKWebViewConfiguration) -> Void)? = nil,
        prepareReplacement: ((WKWebView) -> Void)? = nil,
        validate: ((WKWebView) -> Bool)? = nil
    ) -> WKWebView? {
        coordinatorProvider().replaceLiveWebView(
            for: tab,
            in: windowId,
            reason: reason,
            prepareConfiguration: prepareConfiguration,
            prepareReplacement: prepareReplacement,
            validate: validate
        )
    }

    func trackedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        coordinatorProvider().trackedOwner(containing: webView)
    }

    func primaryTrackedWindowId(for tabId: UUID) -> UUID? {
        coordinatorProvider().primaryTrackedWindowId(for: tabId)
    }

    func windowIDs(for tabId: UUID) -> [UUID] {
        coordinatorProvider().windowIDs(for: tabId)
    }

    func syncTabAcrossWindows(_ tabId: UUID, originatingWebView: WKWebView? = nil) {
        guard let tab = tabLookup(tabId) else { return }
        guard ExtensionUtils.isExtensionOwnedURL(tab.url) == false else { return }
        let coordinator = coordinatorProvider()
        coordinator.syncTab(
            tab,
            to: tab.url,
            originatingWebView: originatingWebView
        )
    }

    func reloadTabAcrossWindows(_ tabId: UUID) {
        guard let tab = tabLookup(tabId) else { return }
        let coordinator = coordinatorProvider()
        coordinator.reloadTab(tab)
    }

    func reloadTab(_ tabId: UUID, in windowId: UUID) {
        guard let tab = tabLookup(tabId) else { return }
        let coordinator = coordinatorProvider()
        coordinator.reloadTab(tab, in: windowId)
    }

    func setMuteState(_ muted: Bool, for tabId: UUID) {
        coordinatorProvider().setMuteState(muted, for: tabId)
    }
}
