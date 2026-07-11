import Foundation
import SumiWebRuntime
import WebKit

/// Read-only ownership capability over the canonical session repository.
/// Consumers that only route/read WebViews do not depend on the runtime graph.
@MainActor
final class WebViewOwnershipQuery {
    private let webViewSessions: WebViewSessionRepository

    init(webViewSessions: WebViewSessionRepository) {
        self.webViewSessions = webViewSessions
    }

    func webView(for tabID: UUID, in windowID: UUID) -> WKWebView? {
        webViewSessions.webView(for: tabID, in: windowID)
    }

    func trackedWebViews(for tabID: UUID) -> [WKWebView] {
        webViewSessions.webViews(for: tabID)
    }

    func trackedLiveWebViews(for tab: Tab) -> [WKWebView] {
        tab.webViewSession.requireBacking(by: webViewSessions)
        return unique(Array(webViewSessions.windowWebViews(for: tab.id).values))
    }

    func suspensionLiveWebViews(for tab: Tab) -> [WKWebView] {
        tab.webViewSession.requireBacking(by: webViewSessions)
        return webViewSessions.queries.allKnownWebViews(for: tab.id)
    }

    func windowIDs(for tabID: UUID) -> [UUID] {
        webViewSessions.windowIDs(for: tabID)
    }

    func primaryWindowID(for tabID: UUID) -> UUID? {
        webViewSessions.primaryWindowID(for: tabID)
    }

    func trackedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        webViewSessions.trackedOwner(containing: webView)
    }

    func untrackedOwnedWebView(for tab: Tab) -> WKWebView? {
        tab.webViewSession.requireBacking(by: webViewSessions)
        guard webViewSessions.windowIDs(for: tab.id).isEmpty,
              let webView = tab.webViewSession.untrackedWebView,
              (webView as? FocusableWKWebView)?.owningTab === tab else {
            return nil
        }
        return webView
    }

    func anyLiveWebView(for tab: Tab) -> WKWebView? {
        tab.webViewSession.requireBacking(by: webViewSessions)
        if let primaryWindowID = primaryWindowID(for: tab.id),
           let primary = webView(for: tab.id, in: primaryWindowID) {
            return primary
        }
        if let tracked = trackedWebViews(for: tab.id).first {
            return tracked
        }
        return untrackedOwnedWebView(for: tab)
    }

    func hasLiveWebView(for tab: Tab) -> Bool {
        anyLiveWebView(for: tab) != nil
    }

    func owns(_ webView: WKWebView, for tab: Tab) -> Bool {
        tab.webViewSession.requireBacking(by: webViewSessions)
        return tab.webViewSession.owns(webView)
    }

    private func unique(_ webViews: [WKWebView]) -> [WKWebView] {
        var seen: Set<ObjectIdentifier> = []
        return webViews.filter {
            seen.insert(ObjectIdentifier($0)).inserted
        }
    }
}
