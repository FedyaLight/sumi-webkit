import Combine
import Foundation
import WebKit

/// Tab-local WebView ownership cache / staging (compatibility mirror).
///
/// Phase 6B: `TabWebViewSessionStore` is the authoritative writer for parked /
/// untracked / primary-assignment notes when a browser runtime is attached.
/// Tab mutators call session `note*` first, then update these fields for readers
/// that still go through Tab accessors.
///
/// - Windowed `webView` + `primaryWindowId`: dual-write cache; live SoT is
///   `WindowWebViewRegistry` via `WebViewCoordinator` / `BrowserWebViewRoutingService`.
/// - Untracked `webView` (`primaryWindowId == nil`): mirrored from session notes.
/// - Parked `existingWebView`: mirrored staging for untracked ensure reuse.
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
