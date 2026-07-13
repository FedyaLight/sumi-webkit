import Foundation
import WebKit

/// Resolves WebViews only for the exact canonical Tab currently exported by
/// the browser bridge. Every returned WebView is revalidated against the same
/// residence authority before it escapes.
@available(macOS 15.5, *)
@MainActor
final class ExtensionExactTabWebViewQuery {
    private weak var tabs: (any ExtensionTabQuery)?
    private weak var residences: (any ExtensionTabWebViewResidenceQuery)?
    private weak var selected: (any ExtensionTabLiveWebViewQuery)?

    init(
        tabs: any ExtensionTabQuery,
        residences: any ExtensionTabWebViewResidenceQuery,
        selected: any ExtensionTabLiveWebViewQuery
    ) {
        self.tabs = tabs
        self.residences = residences
        self.selected = selected
    }

    func liveWebView(for tab: Tab) -> WKWebView? {
        guard isCanonical(tab),
              let webView = selected?.extensionLiveWebView(for: tab),
              owns(webView, tab: tab),
              isCanonical(tab),
              selected?.extensionLiveWebView(for: tab) === webView
        else { return nil }
        return webView
    }

    func untrackedWebView(for tab: Tab) -> WKWebView? {
        guard isCanonical(tab),
              let webView = residences?.extensionUntrackedWebView(for: tab),
              owns(webView, tab: tab),
              isCanonical(tab),
              residences?.extensionUntrackedWebView(for: tab) === webView
        else { return nil }
        return webView
    }

    func currentLiveWebViews(for tab: Tab) -> [WKWebView] {
        guard isCanonical(tab), let residences else { return [] }
        let snapshot = residences.extensionLiveWebViews(for: tab)
            .filter { owns($0, tab: tab) }
        guard isCanonical(tab) else { return [] }
        let current = Set(
            residences.extensionLiveWebViews(for: tab)
                .filter { owns($0, tab: tab) }
                .map(ObjectIdentifier.init)
        )
        return snapshot.filter { current.contains(ObjectIdentifier($0)) }
    }

    func isCanonical(_ tab: Tab) -> Bool {
        tabs?.extensionTab(for: tab.id) === tab
    }

    func contains(_ webView: WKWebView, for tab: Tab) -> Bool {
        currentLiveWebViews(for: tab).contains { $0 === webView }
    }

    private func owns(_ webView: WKWebView, tab: Tab) -> Bool {
        (webView as? FocusableWKWebView)?.owningTab === tab
    }
}
