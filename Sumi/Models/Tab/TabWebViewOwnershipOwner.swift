import Combine
import Foundation
import WebKit
import SumiWebRuntime

/// Tab-local WebView session notes before a browser runtime / coordinator attaches.
///
/// Live SoT after attach is `TabWebViewSessionStore` + `WindowWebViewRegistry`
/// via `WebViewCoordinator` / `BrowserWebViewRoutingService`. This owner only
/// holds a local `TabWebViewSession` for pre-runtime park/ensure paths; it does
/// not expose façade WebView accessors.
@MainActor
final class TabWebViewOwnershipOwner {
    /// Pre-runtime session notes; cleared when adopted into the coordinator store.
    private(set) var localSession: TabWebViewSession

    init(tabId: UUID) {
        localSession = TabWebViewSession(tabId: tabId)
    }

    var isUnloaded: Bool {
        localSession.currentWebView == nil
    }

    func setCurrentWebView(_ webView: WKWebView?) {
        if let webView {
            localSession.untrackedWebView = webView
            localSession.primaryWindowId = nil
            localSession.primaryWebView = nil
        } else {
            localSession.untrackedWebView = nil
            localSession.primaryWebView = nil
        }
    }

    func setExistingWebView(_ webView: WKWebView?) {
        localSession.parkedWebView = webView
    }

    func setPrimaryWindowId(_ primaryWindowId: UUID?) {
        localSession.primaryWindowId = primaryWindowId
        if primaryWindowId != nil {
            localSession.untrackedWebView = nil
        } else {
            localSession.primaryWebView = nil
        }
    }

    func parkExistingWebView(_ webView: WKWebView?) {
        localSession.parkedWebView = webView
    }

    func clearParkedExistingWebView() {
        localSession.parkedWebView = nil
    }

    func adoptParkedWebViewAsCurrent(_ webView: WKWebView) {
        localSession.untrackedWebView = webView
        localSession.primaryWindowId = nil
        localSession.primaryWebView = nil
    }

    func replaceUntrackedWebView(_ webView: WKWebView) {
        localSession.untrackedWebView = webView
        localSession.primaryWindowId = nil
        localSession.primaryWebView = nil
    }

    func assignPrimaryWebView(_ webView: WKWebView, windowId: UUID) {
        localSession.primaryWindowId = windowId
        localSession.primaryWebView = webView
        localSession.untrackedWebView = nil
    }

    func clearCurrentWebViewOwnership() {
        localSession.untrackedWebView = nil
        localSession.primaryWindowId = nil
        localSession.primaryWebView = nil
    }

    func clearAllWebViewOwnership() {
        localSession.clearAll()
    }

    @discardableResult
    func clearCurrentWebViewOwnershipIfIdentical(to webView: WKWebView) -> Bool {
        guard localSession.currentWebView === webView else { return false }
        clearCurrentWebViewOwnership()
        return true
    }

    /// Hands local notes to the coordinator store and clears the Tab-local slot.
    func adoptIntoSessionStore(_ store: TabWebViewSessionStore) {
        store.adoptLocalSession(localSession, for: localSession.tabId)
        localSession = TabWebViewSession(tabId: localSession.tabId)
    }
}

@MainActor
final class TabWebViewRuntime {
    var profileAwaitCancellable: AnyCancellable?
    let reloadPolicyStateOwner = TabReloadPolicyStateOwner()
    let findInPage = FindInPageTabExtension()
}
