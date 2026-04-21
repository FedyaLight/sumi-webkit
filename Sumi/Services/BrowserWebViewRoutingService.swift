import WebKit

@MainActor
final class BrowserWebViewRoutingService {
    typealias TabLookup = @MainActor (UUID) -> Tab?
    typealias IncognitoTabLookup = @MainActor (UUID, UUID) -> Tab?
    typealias WebViewCoordinatorLookup = @MainActor () -> WebViewCoordinator?

    private let tabLookup: TabLookup
    private let incognitoTabLookup: IncognitoTabLookup
    private let coordinatorLookup: WebViewCoordinatorLookup

    init(
        tabLookup: @escaping TabLookup,
        incognitoTabLookup: @escaping IncognitoTabLookup,
        coordinatorLookup: @escaping WebViewCoordinatorLookup
    ) {
        self.tabLookup = tabLookup
        self.incognitoTabLookup = incognitoTabLookup
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

    func createWebView(for tabId: UUID, in windowId: UUID) -> WKWebView {
        guard let coordinator = coordinatorLookup() else {
            preconditionFailure(
                "[WebViewRoutingService] createWebView: WebViewCoordinator is nil (tab \(tabId), window \(windowId))."
            )
        }

        if let incognitoTab = incognitoTabLookup(windowId, tabId) {
            return coordinator.createWebView(for: incognitoTab, in: windowId)
        }

        guard let tab = tabLookup(tabId) else {
            preconditionFailure(
                "[WebViewRoutingService] createWebView: unknown tab \(tabId) in window \(windowId)."
            )
        }

        return coordinator.createWebView(for: tab, in: windowId)
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

    func navigateTabAcrossWindows(_ tabId: UUID, to url: URL) {
        guard let tab = tabLookup(tabId) else { return }
        guard let coordinator = coordinatorLookup() else {
            preconditionFailure(
                "[WebViewRoutingService] navigateTabAcrossWindows: WebViewCoordinator is nil (tab \(tabId))."
            )
        }
        coordinator.syncTab(tab, to: url)
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

    func setMuteState(_ muted: Bool, for tabId: UUID, originatingWindowId: UUID?) {
        guard let coordinator = coordinatorLookup() else {
            preconditionFailure(
                "[WebViewRoutingService] setMuteState: WebViewCoordinator is nil (tab \(tabId))."
            )
        }
        coordinator.setMuteState(
            muted,
            for: tabId,
            excludingWindow: originatingWindowId
        )
    }
}
