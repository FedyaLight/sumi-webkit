import Foundation
import SumiDomain

/// Shared Glance routing policy for native navigation-policy callbacks and
/// WebKit child-view requests. Presentation still resolves the exact physical
/// source through `TabLinkPresentationCommands`.
@MainActor
enum LinkGlanceRouting {
    static func routeExplicit(
        _ url: URL?,
        isRequested: Bool,
        tab: Tab,
        sourceWebView: FocusableWKWebView
    ) -> Bool {
        guard let url,
              url.sumiIsGlancePreviewableLink,
              isRequested
        else {
            return false
        }
        return present(url, tab: tab, sourceWebView: sourceWebView)
    }

    static func routeDynamic(
        _ url: URL?,
        isRequested: Bool,
        tab: Tab,
        sourceWebView: FocusableWKWebView,
        isExtensionOriginated: Bool,
        isMiddleButtonClick: Bool = false
    ) -> Bool {
        guard let url,
              isExtensionOriginated == false,
              isMiddleButtonClick == false,
              isRequested
        else {
            return false
        }
        return present(url, tab: tab, sourceWebView: sourceWebView)
    }

    private static func present(
        _ url: URL,
        tab: Tab,
        sourceWebView: FocusableWKWebView
    ) -> Bool {
        let didPresent = tab.linkPresentationCommands.presentInGlance(
            url,
            from: sourceWebView,
            originRectInWindow: sourceWebView.gestures
                .recentGlanceOriginRect(maxAge: 2)
        )
        if didPresent {
            sourceWebView.consumeGestureForBrowserCommand()
        }
        return didPresent
    }
}
