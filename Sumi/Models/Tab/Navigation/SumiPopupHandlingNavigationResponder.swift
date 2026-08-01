import AppKit
import Foundation
import SumiDomain
import WebKit
import SumiWebRuntime

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
    SumiNavigationActionSourceAndTargetWebViewResponding
{
    private weak var tab: Tab?
    private let permissions: (any PopupPermissionEvaluating)?
    private let childWebViewTransaction: WebKitChildWebViewTransaction

    init(
        tab: Tab,
        permissions: (any PopupPermissionEvaluating)?,
        extensionRequests: (any ExtensionPopupRequestConsuming)?,
        extensionTabs: (any ExtensionExternalTabOpening)?,
        webPopups: (any PhysicalWebPopupOpening)?,
        childTabs: (any WebKitChildTabOpening)?,
        childWindows: (any WebKitChildWindowOpening)?
    ) {
        self.tab = tab
        self.permissions = permissions
        childWebViewTransaction = WebKitChildWebViewTransaction(
            tab: tab,
            permissions: permissions,
            extensionRequests: extensionRequests,
            childSurfaceRouter: WebKitChildSurfaceRouter(
                extensionTabs: extensionTabs,
                webPopups: webPopups,
                childTabs: childTabs,
                childWindows: childWindows
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

    /// WebKit `createWebView` path: merged navigation modifier flags drive routing —
    /// explicit Glance first, then the native context-menu command, dynamic Glance,
    /// and finally the WebKit-requested popup/tab/window disposition.
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
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        guard let targetTab = tab,
              targetTab.hasBrowserRuntime
        else { return .next }

        if let url = navigationAction.url,
           targetTab.isPopupHost,
           SumiSurface.isNativeSurfaceURL(url) {
            return .cancel
        }

        guard let url = navigationAction.url else { return .next }

        let isLinkActivated = !navigationAction.isTargetingNewWindow
            && (navigationAction.navigationType.isLinkActivated
                || (navigationAction.navigationType == .other && navigationAction.isUserInitiated))
        guard isLinkActivated else { return .next }
        guard let sourceWebView = sourceWebView as? FocusableWKWebView else {
            return .cancel
        }
        guard let sourceTab = sourceWebView.owningTab,
              sourceTab.hasBrowserRuntime,
              let sourceDocumentLease = sourceTab.committedDocumentRuntime.lease(
                  for: sourceWebView
              )
        else {
            return .next
        }
        let exactTargetWebView = targetWebView as? FocusableWKWebView
        if let exactTargetWebView {
            guard exactTargetWebView.owningTab === targetTab else {
                return .next
            }
        } else {
            guard sourceTab === targetTab else { return .next }
        }
        let gestureReceipt = sourceWebView.gestures.currentReceipt

        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.popupResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.popupResponder", signpostState)
        }

        let modifierFlags = sourceWebView.gestures.resolvedModifierFlags(
            actionFlags: navigationAction.modifierFlags
        )
        if LinkGlanceRouting.routeExplicit(
            url,
            isRequested: sourceTab.isGlanceTriggerActive(modifierFlags),
            tab: sourceTab,
            sourceWebView: sourceWebView
        ) {
            return .cancel
        }

        guard let targetFrame = navigationAction.targetFrame else { return .next }

        let isExtensionOriginated = SumiPopupNavigationOrigin.isExtensionOriginatedPopupNavigation(
            sourceURL: navigationAction.sourceURL
                ?? sourceWebView.committedURL
                ?? sourceWebView.url,
            requestURL: url
        )
        let isMiddleButtonClick = navigationAction.navigationType.isMiddleButtonClick
        let shouldOpenDynamicGlance = !isExtensionOriginated
            && !isMiddleButtonClick
            && sourceTab.shouldOpenDynamicallyInGlance(
                url: url,
                modifierFlags: modifierFlags
            )
        if LinkGlanceRouting.routeDynamic(
            url,
            isRequested: shouldOpenDynamicGlance,
            tab: sourceTab,
            sourceWebView: sourceWebView,
            isExtensionOriginated: isExtensionOriginated,
            isMiddleButtonClick: isMiddleButtonClick
        ) {
            return .cancel
        }

        let canOpenLinkInCurrentTab: Bool = {
            guard targetTab.usesPinnedLinkPolicy,
                  navigationAction.isForMainFrame else {
                return true
            }
            let exactTargetURL = targetWebView?.committedURL
                ?? targetWebView?.url
                ?? targetFrame.url
            guard let targetURL = exactTargetURL,
                  targetURL.sumiIsEmpty == false,
                  let targetHost = targetURL.host,
                  let destinationHost = url.host
            else {
                return false
            }
            let navigatingAwayFromPinnedTab = destinationHost != targetHost
            return !navigatingAwayFromPinnedTab
        }()

        let behavior = SumiLinkOpenBehavior(
            buttonIsMiddle: navigationAction.navigationType.isMiddleButtonClick,
            modifierFlags: modifierFlags,
            switchToNewTabWhenOpenedPreference: false,
            canOpenLinkInCurrentTab: canOpenLinkInCurrentTab,
            shouldSelectNewTab: true
        )

        switch behavior {
        case .currentTab:
            return .next
        case .newTab, .newWindow:
            guard let tabContext = sourceTab.popupPermissionTabContext(for: sourceWebView)
            else {
                return .cancel
            }
            let activationState = sourceWebView.popupUserActivation.claim(
                webKitUserInitiated: nil,
                navigationActionUserInitiated: navigationAction.isUserInitiated
            )
            let request = SumiPopupPermissionRequest.fromSumiNavigationAction(
                navigationAction,
                activationState: activationState
            )
            guard let permissions else { return .cancel }
            let permissionResult = await permissions.evaluate(
                request,
                tabContext: tabContext
            )
            guard permissionResult.isAllowed,
                  sourceTab.hasBrowserRuntime,
                  targetTab.hasBrowserRuntime,
                  sourceWebView.owningTab === sourceTab,
                  sourceTab.committedDocumentRuntime.lease(
                      for: sourceWebView
                  ) == sourceDocumentLease,
                  tabContext.isCurrentPage(),
                  exactTargetWebView?.owningTab === targetTab
                    || (exactTargetWebView == nil && sourceTab === targetTab)
            else {
                return .cancel
            }

            let disposition: TabLinkDisposition
            switch behavior {
            case .currentTab:
                preconditionFailure("Current-tab behavior returned from a new-surface branch")
            case .newTab(let selected):
                disposition = .newTab(selected: selected)
            case .newWindow(let selected):
                disposition = .newWindow(selected: selected)
            }
            if sourceTab.linkPresentationCommands.open(
                url,
                from: sourceWebView,
                disposition: disposition
            ) {
                sourceWebView.gestures.clear(ifCurrent: gestureReceipt)
            }
            return .cancel
        }
    }

}

private extension SumiNavigationAction {
    var isNativeGlanceLinkActivation: Bool {
        navigationType.isLinkActivated
            || (navigationType == .other && isUserInitiated)
    }
}
