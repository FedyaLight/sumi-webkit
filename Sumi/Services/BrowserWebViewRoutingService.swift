import WebKit

@MainActor
final class BrowserWebViewRoutingService {
    typealias TabLookup = @MainActor (UUID) -> Tab?
    /// May return nil before the shell binds a coordinator (startup / early Tab mutators).
    typealias WebViewCoordinatorProvider = @MainActor () -> WebViewCoordinator?

    private let tabLookup: TabLookup
    private let coordinatorProvider: WebViewCoordinatorProvider

    init(
        tabLookup: @escaping TabLookup,
        coordinatorProvider: @escaping WebViewCoordinatorProvider
    ) {
        self.tabLookup = tabLookup
        self.coordinatorProvider = coordinatorProvider
    }

    private func requireCoordinator(
        operation: String = #function
    ) -> WebViewCoordinator {
        guard let coordinator = coordinatorProvider() else {
            preconditionFailure(
                "WebViewCoordinator is nil during \(operation). Bind it before WebView routing."
            )
        }
        return coordinator
    }

    func webView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        requireCoordinator().getWebView(for: tabId, in: windowId)
    }

    func windowOwnedWebView(for tab: Tab, in windowId: UUID) -> WKWebView? {
        webView(for: tab.id, in: windowId)
    }

    @discardableResult
    func getOrCreateWebView(for tab: Tab, in windowId: UUID) -> WKWebView? {
        requireCoordinator().getOrCreateWebView(for: tab, in: windowId)
    }

    /// Live WebViews known to the coordinator registry for this tab.
    func trackedWebViews(for tabId: UUID) -> [WKWebView] {
        requireCoordinator().getAllWebViews(for: tabId)
    }

    /// Prefer a window-tracked WebView; fall back to an untracked tab-owned instance
    /// (popup / pre-window / Glance materialization) via the coordinator.
    func anyLiveWebView(for tab: Tab) -> WKWebView? {
        requireCoordinator().anyLiveWebView(for: tab)
    }

    func ownsLiveWebView(_ webView: WKWebView, for tab: Tab) -> Bool {
        requireCoordinator().ownsLiveWebView(webView, for: tab)
    }

    func hasLiveWebView(for tab: Tab) -> Bool {
        requireCoordinator().hasLiveWebView(for: tab)
    }

    func hasUntrackedOwnedWebView(for tab: Tab) -> Bool {
        requireCoordinator().untrackedOwnedWebView(for: tab) != nil
    }

    func assignWebView(_ webView: WKWebView, to tab: Tab, in windowId: UUID) {
        requireCoordinator().assignWebView(webView, to: tab, in: windowId)
    }

    func installUntrackedOwnedWebView(_ webView: WKWebView, for tab: Tab) {
        requireCoordinator().installUntrackedOwnedWebView(webView, for: tab)
    }

    @discardableResult
    func ensureUntrackedOwnedWebView(for tab: Tab) -> WKWebView? {
        requireCoordinator().ensureUntrackedOwnedWebView(for: tab)
    }

    func releaseUntrackedOwnedWebView(for tab: Tab) {
        requireCoordinator().releaseUntrackedOwnedWebView(for: tab)
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
        requireCoordinator().replaceLiveWebView(
            for: tab,
            in: windowId,
            reason: reason,
            prepareConfiguration: prepareConfiguration,
            prepareReplacement: prepareReplacement,
            validate: validate
        )
    }

    func trackedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        requireCoordinator().trackedOwner(containing: webView)
    }

    func primaryTrackedWindowId(for tabId: UUID) -> UUID? {
        requireCoordinator().primaryTrackedWindowId(for: tabId)
    }

    func windowIDs(for tabId: UUID) -> [UUID] {
        requireCoordinator().windowIDs(for: tabId)
    }

    func syncTabAcrossWindows(_ tabId: UUID, originatingWebView: WKWebView? = nil) {
        guard let tab = tabLookup(tabId) else { return }
        guard ExtensionUtils.isExtensionOwnedURL(tab.url) == false else { return }
        let coordinator = requireCoordinator()
        coordinator.syncTab(
            tab,
            to: tab.url,
            originatingWebView: originatingWebView
        )
    }

    func reloadTabAcrossWindows(_ tabId: UUID) {
        guard let tab = tabLookup(tabId) else { return }
        requireCoordinator().reloadTab(tab)
    }

    func reloadTab(_ tabId: UUID, in windowId: UUID) {
        guard let tab = tabLookup(tabId) else { return }
        requireCoordinator().reloadTab(tab, in: windowId)
    }

    func setMuteState(_ muted: Bool, for tabId: UUID) {
        requireCoordinator().setMuteState(muted, for: tabId)
    }

    // MARK: - Phase 6B session notes

    /// Best-effort: no-ops when the coordinator is not bound yet (Tab mirror still written).
    func noteParkedWebView(_ webView: WKWebView?, for tabId: UUID) {
        coordinatorProvider()?.tabWebViewSessionStore.noteParkedWebView(webView, for: tabId)
    }

    func noteUntrackedWebView(_ webView: WKWebView?, for tabId: UUID) {
        coordinatorProvider()?.tabWebViewSessionStore.noteUntrackedWebView(webView, for: tabId)
    }

    func notePrimaryAssignment(windowId: UUID, for tabId: UUID) {
        coordinatorProvider()?.tabWebViewSessionStore.notePrimaryAssignment(
            windowId: windowId,
            for: tabId
        )
    }

    func clearPrimaryAssignment(for tabId: UUID) {
        coordinatorProvider()?.tabWebViewSessionStore.clearPrimaryAssignment(for: tabId)
    }

    func clearWebViewSession(for tabId: UUID) {
        coordinatorProvider()?.tabWebViewSessionStore.clearAll(for: tabId)
    }
}
