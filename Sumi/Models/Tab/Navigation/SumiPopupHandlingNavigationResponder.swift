import AppKit
import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit

@MainActor
final class SumiGlanceNavigationResponder: SumiNavigationActionSourceWebViewResponding {
    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        sourceWebView: WKWebView?,
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        guard let sourceWebView = sourceWebView as? FocusableWKWebView,
              let sourceTab = sourceWebView.owningTab,
              sourceTab.hasBrowserRuntime,
              let url = navigationAction.url,
              url.sumiIsGlancePreviewableLink,
              navigationAction.isNativeGlanceLinkActivation
        else { return .next }

        let flags = navigationAction.modifierFlags.intersection([.command, .option, .control, .shift])
        let modifierFlags = sourceWebView.gestures.resolvedModifierFlags(
            actionFlags: flags
        )
        guard sourceTab.navigationRuntime.permissionRuntime
            .isActiveGlancePreviewSurface(sourceTab.id, sourceWebView) == false
        else {
            return .next
        }
        guard sourceTab.isGlanceTriggerActive(modifierFlags) else { return .next }

        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.glanceResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.glanceResponder", signpostState)
        }

        if LinkGlanceRouting.routeExplicit(
            url,
            isRequested: true,
            tab: sourceTab,
            sourceWebView: sourceWebView
        ) {
            return .cancel
        }
        return .next
    }
}

@MainActor
final class SumiPopupHandlingNavigationResponder:
    SumiNavigationActionSourceAndTargetWebViewResponding {
    private let linkNavigationTransaction: PopupLinkNavigationTransaction
    private let childWebViewTransaction: WebKitChildWebViewTransaction

    init(
        tab: Tab,
        permissions: (any PopupPermissionEvaluating)?,
        extensionRequests: (any ExtensionPopupRequestConsuming)?,
        extensionTabs: (any ExtensionExternalTabOpening)?,
        webPopups: (any PhysicalWebPopupOpening)?,
        automaticGlance: (any AutomaticGlanceOpening)? = nil,
        childTabs: (any WebKitChildTabOpening)?,
        childWindows: (any WebKitChildWindowOpening)?
    ) {
        linkNavigationTransaction = PopupLinkNavigationTransaction(
            tab: tab,
            permissions: permissions,
            automaticGlance: automaticGlance
        )
        childWebViewTransaction = WebKitChildWebViewTransaction(
            tab: tab,
            permissions: permissions,
            extensionRequests: extensionRequests,
            presentationRouter: WebKitChildPresentationRouter(
                automaticGlance: automaticGlance,
                childSurfaceRouter: WebKitChildSurfaceRouter(
                    extensionTabs: extensionTabs,
                    webPopups: webPopups,
                    childTabs: childTabs,
                    childWindows: childWindows
                )
            )
        )
    }

    func createWebView(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        childWebViewTransaction.openSynchronously(
            from: webView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures
        )
    }

    /// WebKit `createWebView` path: explicit preview commands settle immediately;
    /// automatic Glance is considered by the child transaction only after popup
    /// admission and ordinary popup/tab/window disposition are known.
    func createWebViewAsync(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) async -> WKWebView? {
        await childWebViewTransaction.open(
            from: webView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures
        )
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        sourceWebView: WKWebView?,
        targetWebView: WKWebView?,
        preferences: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        await linkNavigationTransaction.decidePolicy(
            for: navigationAction,
            sourceWebView: sourceWebView,
            targetWebView: targetWebView,
            preferences: &preferences
        )
    }
}

private extension SumiNavigationAction {
    var isNativeGlanceLinkActivation: Bool {
        navigationType.isLinkActivated
            || (navigationType == .other && isUserInitiated)
    }
}
