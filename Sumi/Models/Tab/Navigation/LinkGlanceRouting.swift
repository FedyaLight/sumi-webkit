import Foundation
import SumiDomain
import WebKit

/// Shared Glance routing policy for native navigation-policy callbacks and
/// WebKit child-view requests. Presentation still resolves the exact physical
/// source through `TabLinkPresentationCommands`.
@MainActor
enum LinkGlanceRouting {
    struct ChildWebViewRequest {
        let navigationAction: WKNavigationAction
        let modifierFlags: NSEvent.ModifierFlags
        let isMiddleButtonClick: Bool
        let isExtensionOriginated: Bool
        let gestureReceipt: WebViewGestureReceipt?
    }

    static func routeChildWebViewRequest(
        _ request: ChildWebViewRequest,
        tab: Tab,
        sourceWebView: FocusableWKWebView
    ) -> Bool {
        let targetURL = request.navigationAction.request.url
        let behavior = SumiLinkOpenBehavior(
            buttonIsMiddle: request.isMiddleButtonClick,
            modifierFlags: request.modifierFlags,
            switchToNewTabWhenOpenedPreference: false
        )
        let isActivePreview = tab.navigationRuntime.permissionRuntime
            .isActiveGlancePreviewSurface(tab.id, sourceWebView)
        let isUserActivated = request.navigationAction.navigationType
            == .linkActivated || request.navigationAction.isUserInitiated == true

        if isActivePreview, behavior == .currentTab, isUserActivated {
            sourceWebView.load(request.navigationAction.request)
            sourceWebView.gestures.clear(ifCurrent: request.gestureReceipt)
            return true
        }
        if isActivePreview,
           let targetURL,
           let disposition = disposition(for: behavior),
           tab.linkPresentationCommands.open(
               targetURL,
               from: sourceWebView,
               disposition: disposition
           ) {
            sourceWebView.consumeGestureForBrowserCommand()
            return true
        }
        if routeExplicit(
            targetURL,
            isRequested: !isActivePreview
                && tab.isGlanceTriggerActive(request.modifierFlags),
            tab: tab,
            sourceWebView: sourceWebView
        ) {
            return true
        }

        let isDynamicTarget = targetURL.map {
            tab.shouldOpenDynamicallyInGlance(
                url: $0,
                modifierFlags: request.modifierFlags
            )
        } ?? false
        return routeDynamic(
            targetURL,
            isRequested: isDynamicTarget,
            tab: tab,
            sourceWebView: sourceWebView,
            isExtensionOriginated: request.isExtensionOriginated,
            isMiddleButtonClick: request.isMiddleButtonClick
        )
    }

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

    private static func disposition(
        for behavior: SumiLinkOpenBehavior
    ) -> TabLinkDisposition? {
        switch behavior {
        case .currentTab:
            nil
        case .newTab(let selected):
            .newTab(selected: selected)
        case .newWindow(let selected):
            .newWindow(selected: selected)
        }
    }
}
