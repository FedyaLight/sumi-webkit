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
