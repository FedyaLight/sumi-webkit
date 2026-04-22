import WebKit

@MainActor
final class BrowserWebViewRoutingService {
    typealias TabLookup = @MainActor (UUID) -> Tab?
    typealias WebViewCoordinatorLookup = @MainActor () -> WebViewCoordinator?

    private let tabLookup: TabLookup
    private let coordinatorLookup: WebViewCoordinatorLookup

    init(
        tabLookup: @escaping TabLookup,
        coordinatorLookup: @escaping WebViewCoordinatorLookup
    ) {
        self.tabLookup = tabLookup
        self.coordinatorLookup = coordinatorLookup
    }

    func webView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        guard let coordinator = coordinatorLookup() else {
            preconditionFailure(
                "[WebViewRoutingService] webView: WebViewCoordinator is nil (tab \(tabId), window \(windowId))."
            )
        }
        return coordinator.getWebView(for: tabId, in: windowId)
    }

    func syncTabAcrossWindows(_ tabId: UUID, originatingWebView: WKWebView? = nil) {
        guard let tab = tabLookup(tabId) else { return }
        guard let coordinator = coordinatorLookup() else {
            preconditionFailure(
                "[WebViewRoutingService] syncTabAcrossWindows: WebViewCoordinator is nil (tab \(tabId))."
            )
        }
        coordinator.syncTab(
            tab,
            to: tab.url,
            originatingWebView: originatingWebView
        )
    }

    func reloadTabAcrossWindows(_ tabId: UUID) {
        guard let tab = tabLookup(tabId) else { return }
        guard let coordinator = coordinatorLookup() else {
            preconditionFailure(
                "[WebViewRoutingService] reloadTabAcrossWindows: WebViewCoordinator is nil (tab \(tabId))."
            )
        }
        coordinator.reloadTab(tab)
    }

    func setMuteState(_ muted: Bool, for tabId: UUID) {
        guard let coordinator = coordinatorLookup() else {
            preconditionFailure(
                "[WebViewRoutingService] setMuteState: WebViewCoordinator is nil (tab \(tabId))."
            )
        }
        coordinator.setMuteState(muted, for: tabId)
    }
}
