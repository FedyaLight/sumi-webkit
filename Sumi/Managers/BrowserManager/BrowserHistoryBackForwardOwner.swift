import AppKit
import WebKit

/// Back/forward navigation collaborator for `BrowserHistoryNavigationOwner`.
/// Not a BrowserManager lazy Owner — constructed inside the navigation façade.
@MainActor
final class BrowserHistoryBackForwardOwner {
    private let activeWindow: @MainActor @Sendable () -> BrowserWindowState?
    private let activePageTab: @MainActor @Sendable (BrowserWindowState) -> Tab?
    private let activePageWebView: @MainActor @Sendable (BrowserWindowState) -> WKWebView?
    private let webView: @MainActor @Sendable (UUID, UUID) -> WKWebView?
    private let navigateBack: @MainActor @Sendable (WKWebView) -> Void
    private let navigateForward: @MainActor @Sendable (WKWebView) -> Void

    init(
        activeWindow: @escaping @MainActor @Sendable () -> BrowserWindowState?,
        activePageTab: @escaping @MainActor @Sendable (BrowserWindowState) -> Tab?,
        activePageWebView: @escaping @MainActor @Sendable (BrowserWindowState) -> WKWebView?,
        webView: @escaping @MainActor @Sendable (UUID, UUID) -> WKWebView?,
        navigateBack: @escaping @MainActor @Sendable (WKWebView) -> Void,
        navigateForward: @escaping @MainActor @Sendable (WKWebView) -> Void
    ) {
        self.activeWindow = activeWindow
        self.activePageTab = activePageTab
        self.activePageWebView = activePageWebView
        self.webView = webView
        self.navigateBack = navigateBack
        self.navigateForward = navigateForward
    }

    var canGoBackInActiveWindow: Bool {
        guard let window = activeWindow() else { return false }
        return canGoBack(in: window)
    }

    var canGoForwardInActiveWindow: Bool {
        guard let window = activeWindow() else { return false }
        return canGoForward(in: window)
    }

    func canGoBack(in windowState: BrowserWindowState) -> Bool {
        resolvedActivePageWebView(in: windowState)?.canGoBack ?? false
    }

    func canGoForward(in windowState: BrowserWindowState) -> Bool {
        resolvedActivePageWebView(in: windowState)?.canGoForward ?? false
    }

    func goBackInActiveWindow() {
        guard let window = activeWindow() else { return }
        goBack(in: window)
    }

    func goForwardInActiveWindow() {
        guard let window = activeWindow() else { return }
        goForward(in: window)
    }

    func goBack(in windowState: BrowserWindowState) {
        guard let webView = resolvedActivePageWebView(in: windowState),
              webView.canGoBack
        else { return }
        navigateBack(webView)
    }

    func goForward(in windowState: BrowserWindowState) {
        guard let webView = resolvedActivePageWebView(in: windowState),
              webView.canGoForward
        else { return }
        navigateForward(webView)
    }

    private func resolvedActivePageWebView(in windowState: BrowserWindowState) -> WKWebView? {
        guard let currentTab = activePageTab(windowState)
        else {
            return nil
        }
        return activePageWebView(windowState)
            ?? webView(currentTab.id, windowState.id)
    }
}
