import Combine
import Foundation
import WebKit

/// Tab-local WebView ownership cache / staging.
///
/// - Windowed `webView` + `primaryWindowId`: coordinator-synced cache. Live SoT is
///   `WindowWebViewRegistry` via `WebViewCoordinator` / `BrowserWebViewRoutingService`.
/// - Untracked `webView` (`primaryWindowId == nil`): Tab slot write-gated by coordinator
///   install/release (and Tab ensure path which installs through the same mutators).
/// - Parked `existingWebView`: Tab-local staging for untracked ensure reuse; not registry material.
///
/// External production code must not mutate these fields; CI enforces Tab + WebViewCoordinator
/// as the sole writers.
@MainActor
final class TabWebViewOwnershipOwner {
    private(set) var webView: WKWebView?
    private(set) var existingWebView: WKWebView?
    private(set) var primaryWindowId: UUID?

    var assignedWebView: WKWebView? {
        primaryWindowId != nil ? webView : nil
    }

    var isUnloaded: Bool {
        webView == nil
    }

    func setCurrentWebView(_ webView: WKWebView?) {
        self.webView = webView
    }

    func setExistingWebView(_ webView: WKWebView?) {
        existingWebView = webView
    }

    func setPrimaryWindowId(_ primaryWindowId: UUID?) {
        self.primaryWindowId = primaryWindowId
    }

    func parkExistingWebView(_ webView: WKWebView?) {
        existingWebView = webView
    }

    func clearParkedExistingWebView() {
        existingWebView = nil
    }

    func adoptParkedWebViewAsCurrent(_ webView: WKWebView) {
        self.webView = webView
    }

    func replaceUntrackedWebView(_ webView: WKWebView) {
        self.webView = webView
        primaryWindowId = nil
    }

    func assignPrimaryWebView(_ webView: WKWebView, windowId: UUID) {
        self.webView = webView
        primaryWindowId = windowId
    }

    func clearCurrentWebViewOwnership() {
        webView = nil
        primaryWindowId = nil
    }

    func clearAllWebViewOwnership() {
        webView = nil
        existingWebView = nil
        primaryWindowId = nil
    }

    @discardableResult
    func clearCurrentWebViewOwnershipIfIdentical(to webView: WKWebView) -> Bool {
        guard self.webView === webView else { return false }
        clearCurrentWebViewOwnership()
        return true
    }
}

@MainActor
final class TabWebViewRuntime {
    var profileAwaitCancellable: AnyCancellable?
    let reloadPolicyStateOwner = TabReloadPolicyStateOwner()
    let findInPage = FindInPageTabExtension()
}
