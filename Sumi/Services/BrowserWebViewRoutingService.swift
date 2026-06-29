import OSLog
import WebKit

@MainActor
final class BrowserWebViewRoutingService {
    typealias TabLookup = @MainActor (UUID) -> Tab?
    typealias WebViewCoordinatorLookup = @MainActor () -> WebViewCoordinator?

    private static let log = Logger.sumi(category: "WebViewRoutingService")

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
        guard let coordinator = resolvedCoordinator(
            for: "webView",
            tabId: tabId,
            windowId: windowId
        ) else { return nil }
        return coordinator.getWebView(for: tabId, in: windowId)
    }

    func syncTabAcrossWindows(_ tabId: UUID, originatingWebView: WKWebView? = nil) {
        guard let tab = tabLookup(tabId) else { return }
        guard ExtensionUtils.isExtensionOwnedURL(tab.url) == false else { return }
        guard let coordinator = resolvedCoordinator(
            for: "syncTabAcrossWindows",
            tabId: tabId
        ) else { return }
        coordinator.syncTab(
            tab,
            to: tab.url,
            originatingWebView: originatingWebView
        )
    }

    func reloadTabAcrossWindows(_ tabId: UUID) {
        guard let tab = tabLookup(tabId) else { return }
        guard let coordinator = resolvedCoordinator(
            for: "reloadTabAcrossWindows",
            tabId: tabId
        ) else { return }
        coordinator.reloadTab(tab)
    }

    func setMuteState(_ muted: Bool, for tabId: UUID) {
        guard let coordinator = resolvedCoordinator(
            for: "setMuteState",
            tabId: tabId
        ) else { return }
        coordinator.setMuteState(muted, for: tabId)
    }

    private func resolvedCoordinator(
        for operation: String,
        tabId: UUID,
        windowId: UUID? = nil
    ) -> WebViewCoordinator? {
        guard let coordinator = coordinatorLookup() else {
            let windowDescription = windowId?.uuidString ?? "none"
            Self.log.error(
                "Dropping \(operation, privacy: .public) because WebViewCoordinator is nil. tab=\(tabId.uuidString, privacy: .public) window=\(windowDescription, privacy: .public)"
            )
            return nil
        }
        return coordinator
    }
}
