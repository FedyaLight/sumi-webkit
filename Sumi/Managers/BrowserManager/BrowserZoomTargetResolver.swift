import Foundation
import WebKit

struct BrowserZoomTarget {
    let tab: Tab
    let webView: WKWebView
    let domain: String
    let profileID: UUID?
    /// Whether `profileID` names a private partition, whose zoom preferences
    /// must never be persisted.
    let isEphemeralProfile: Bool
}

@MainActor
final class BrowserZoomTargetResolver {
    private let activePages: ActivePageResolver
    private let tabs: TabCollectionMembershipOwner
    private let windowTabs: BrowserWindowTabContext
    private let webViews: BrowserWebViewRoutingService

    init(
        activePages: ActivePageResolver,
        tabs: TabCollectionMembershipOwner,
        windowTabs: BrowserWindowTabContext,
        webViews: BrowserWebViewRoutingService
    ) {
        self.activePages = activePages
        self.tabs = tabs
        self.windowTabs = windowTabs
        self.webViews = webViews
    }

    func activeTarget(in window: BrowserWindowState) -> BrowserZoomTarget? {
        guard let page = activePages.resolve(in: window),
              let webView = page.presentationWebView else {
            return nil
        }
        return makeTarget(tab: page.tab, webView: webView)
    }

    func target(for tabID: UUID, activeWindow: BrowserWindowState?) -> BrowserZoomTarget? {
        guard let tab = tabs.tab(for: tabID),
              let window = windowTabs.windowState(containing: tab) ?? activeWindow,
              let webView = webViews.webView(for: tabID, in: window.id) else {
            return nil
        }
        return makeTarget(tab: tab, webView: webView)
    }

    func tab(_ tabID: UUID) -> Tab? {
        tabs.tab(for: tabID)
    }

    func windowState(for tab: Tab) -> BrowserWindowState? {
        windowTabs.windowState(containing: tab)
    }

    func makeTarget(tab: Tab, webView: WKWebView) -> BrowserZoomTarget {
        let profile = tab.resolveProfile()
        return BrowserZoomTarget(
            tab: tab,
            webView: webView,
            domain: tab.url.host ?? tab.url.absoluteString,
            profileID: profile?.id ?? tab.profileId,
            isEphemeralProfile: profile?.isEphemeral ?? tab.isEphemeral
        )
    }
}
