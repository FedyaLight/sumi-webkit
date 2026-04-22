import Foundation
import WebKit

@MainActor
extension PeekManager {
    func dismissPeek(reason: PeekDismissReason = .close) {
        guard isActive || currentSession != nil else { return }

        if reason == .close {
            webViewCoordinator?.tearDownForDismissal()
        }

        isActive = false
        webView = nil
        webViewCoordinator = nil
        NotificationCenter.default.post(name: .peekDidDeactivate, object: self)
        currentSession = nil
    }

    func moveToSplitView() {
        guard let session = currentSession,
              let browserManager,
              let windowState = windowRegistry?.activeWindow else { return }

        let extractedWebView = webViewCoordinator?.detachWebViewForTransfer()

        let newTab: Tab
        if let webView = extractedWebView {
            newTab = browserManager.tabManager.createNewTabWithWebView(
                url: session.currentURL.absoluteString,
                in: browserManager.tabManager.currentSpace,
                existingWebView: webView
            )
        } else {
            newTab = browserManager.tabManager.createNewTab(
                url: session.currentURL.absoluteString,
                in: browserManager.tabManager.currentSpace
            )
        }

        browserManager.splitManager.enterSplit(with: newTab, placeOn: .right, in: windowState)
        browserManager.selectTab(newTab)
        dismissPeek(reason: .moveToSplit)
    }

    func moveToNewTab() {
        guard let session = currentSession,
              let browserManager,
              let coordinator = webViewCoordinator else { return }

        let extractedWebView = coordinator.detachWebViewForTransfer()
        let newTab = browserManager.tabManager.createNewTabWithWebView(
            url: session.currentURL.absoluteString,
            in: browserManager.tabManager.currentSpace,
            existingWebView: extractedWebView
        )

        browserManager.selectTab(newTab)
        dismissPeek(reason: .promoteToTab)
    }

    // MARK: - WebView Management

    func createWebView() -> PeekWebView {
        if let existingWebView = webView {
            return existingWebView
        }

        guard let currentSession else {
            assertionFailure("PeekManager.createWebView called without an active session")
            return PeekWebView(session: PeekSession(
                targetURL: URL(string: "about:blank")!,
                windowId: windowRegistry?.activeWindow?.id ?? UUID()
            ))
        }

        var newWebView = PeekWebView(session: currentSession)
        newWebView.peekManager = self
        return newWebView
    }
}
