import AppKit
import Foundation
import SumiDomain
import WebKit

/// Admits one `WKUIDelegate.createWebView` request against the exact source
/// document, evaluates popup permission, and commits only while that document
/// lease is still current. Sync and async WebKit entry points share the same
/// preparation and commit state machine.
@MainActor
final class WebKitChildWebViewTransaction {
    private struct PendingRequest {
        let tab: Tab
        let sourceWebView: FocusableWKWebView
        let sourceDocumentLease: TabMainFrameDocumentLease
        let permissionContext: SumiPopupPermissionTabContext
        let permissionRequest: SumiPopupPermissionRequest
        let childRequest: WebKitChildSurfaceRouter.Request
        let modifierFlags: NSEvent.ModifierFlags
        let isMiddleButtonClick: Bool
        let shouldDownload: Bool
    }

    private enum Preparation {
        case handled
        case rejected
        case pending(PendingRequest)
    }

    private weak var tab: Tab?
    private let permissions: (any PopupPermissionEvaluating)?
    private let extensionRequests: (any ExtensionPopupRequestConsuming)?
    private let automaticGlance: (any AutomaticGlanceOpening)?
    private let childSurfaceRouter: WebKitChildSurfaceRouter

    init(
        tab: Tab,
        permissions: (any PopupPermissionEvaluating)?,
        extensionRequests: (any ExtensionPopupRequestConsuming)?,
        automaticGlance: (any AutomaticGlanceOpening)?,
        childSurfaceRouter: WebKitChildSurfaceRouter
    ) {
        self.tab = tab
        self.permissions = permissions
        self.extensionRequests = extensionRequests
        self.automaticGlance = automaticGlance
        self.childSurfaceRouter = childSurfaceRouter
    }

    func open(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) async -> WKWebView? {
        switch prepare(
            from: webView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures
        ) {
        case .handled, .rejected:
            return nil
        case .pending(let pending):
            guard let permissions else { return nil }
            let result = await permissions.evaluate(
                pending.permissionRequest,
                tabContext: pending.permissionContext
            )
            return commit(pending, permissionResult: result)
        }
    }

    func openSynchronously(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        switch prepare(
            from: webView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures
        ) {
        case .handled, .rejected:
            return nil
        case .pending(let pending):
            guard let permissions else { return nil }
            let result = permissions
                .evaluateSynchronouslyForWebKitFallback(
                    pending.permissionRequest,
                    tabContext: pending.permissionContext
                )
            return commit(pending, permissionResult: result)
        }
    }

    private func prepare(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> Preparation {
        guard let tab,
              tab.hasBrowserRuntime,
              let sourceWebView = webView as? FocusableWKWebView,
              sourceWebView.owningTab === tab,
              let sourceDocumentLease = tab.committedDocumentRuntime.lease(
                  for: sourceWebView
              ),
              configuration.websiteDataStore ===
                sourceWebView.configuration.websiteDataStore
        else {
            return .rejected
        }

        let gestureReceipt = sourceWebView.gestures.currentReceipt
        let sourceURL = navigationAction.sumiWebKitSourceURL
            ?? sourceWebView.committedURL
            ?? sourceWebView.url
        let targetURL = navigationAction.request.url
        let isExtensionOriginated = SumiPopupNavigationOrigin
            .isExtensionOriginatedPopupNavigation(
                sourceURL: sourceURL,
                requestURL: targetURL
            )

        if let targetURL,
           SumiPopupNavigationOrigin
            .isExtensionOriginatedExternalPopupNavigation(
                sourceURL: sourceURL,
                requestURL: targetURL
            ),
           extensionRequests?
            .consumeRecentlyOpenedExtensionTabRequestIfLoaded(
                for: targetURL
            ) == true {
            return .handled
        }

        let navigationFlags = sourceWebView.gestures.resolvedModifierFlags(
            actionFlags: navigationAction.modifierFlags
        )
        let isMiddleButtonClick = navigationAction.buttonNumber == 2
            || sourceWebView.gestures.hasRecentAuxiliaryMouseDown
        if LinkGlanceRouting.routeChildWebViewRequest(
            LinkGlanceRouting.ChildWebViewRequest(
                navigationAction: navigationAction,
                modifierFlags: navigationFlags,
                isMiddleButtonClick: isMiddleButtonClick,
                isExtensionOriginated: isExtensionOriginated,
                gestureReceipt: gestureReceipt
            ),
            tab: tab,
            sourceWebView: sourceWebView
        ) {
            return .handled
        }

        let behavior = SumiLinkOpenBehavior(
            buttonIsMiddle: isMiddleButtonClick,
            modifierFlags: navigationFlags,
            switchToNewTabWhenOpenedPreference: false,
            canOpenLinkInCurrentTab: false,
            shouldSelectNewTab: true
        )
        let policy = SumiNewWindowPolicy(
            windowFeatures,
            linkOpenBehavior: behavior,
            preferTabsToWindows: true
        )
        guard let permissionContext = tab.popupPermissionTabContext(
            for: sourceWebView
        ),
              permissions != nil
        else {
            return .rejected
        }
        let activationState = sourceWebView.popupUserActivation.claim(
            webKitUserInitiated: navigationAction.isUserInitiated
        )
        let permissionRequest = SumiPopupPermissionRequest
            .fromWKNavigationAction(
                navigationAction,
                path: .uiDelegateCreateWebView,
                activationState: activationState,
                isExtensionOriginated: isExtensionOriginated
            )
        return .pending(
            PendingRequest(
                tab: tab,
                sourceWebView: sourceWebView,
                sourceDocumentLease: sourceDocumentLease,
                permissionContext: permissionContext,
                permissionRequest: permissionRequest,
                childRequest: WebKitChildSurfaceRouter.Request(
                    configuration: configuration,
                    navigationRequest: navigationAction.request,
                    windowFeatures: windowFeatures,
                    sourceWebView: sourceWebView,
                    sourceURL: sourceURL,
                    policy: policy,
                    isExtensionOriginated: isExtensionOriginated,
                    gestureReceipt: gestureReceipt
                ),
                modifierFlags: navigationFlags,
                isMiddleButtonClick: isMiddleButtonClick,
                shouldDownload: navigationAction.shouldDownload
            )
        )
    }

    private func commit(
        _ pending: PendingRequest,
        permissionResult: SumiPopupPermissionResult
    ) -> WKWebView? {
        guard permissionResult.isAllowed,
              pending.tab.hasBrowserRuntime,
              pending.sourceWebView.owningTab === pending.tab,
              pending.tab.committedDocumentRuntime.lease(
                  for: pending.sourceWebView
              ) == pending.sourceDocumentLease,
              pending.permissionContext.isCurrentPage(),
              pending.childRequest.configuration.websiteDataStore ===
                pending.sourceWebView.configuration.websiteDataStore
        else {
            return nil
        }
        if AutomaticGlancePolicy.shouldPresent(
            pending.childRequest.navigationRequest.url,
            from: pending.tab,
            ordinaryPolicy: pending.childRequest.policy,
            modifierFlags: pending.modifierFlags,
            isExtensionOriginated: pending.childRequest.isExtensionOriginated,
            isMiddleButtonClick: pending.isMiddleButtonClick,
            shouldDownload: pending.shouldDownload
        ),
           let targetURL = pending.childRequest.navigationRequest.url,
           let webView = automaticGlance?.openWebKitChild(
               configuration: pending.childRequest.configuration,
               requestURL: targetURL,
               from: pending.sourceWebView,
               originRectInWindow: pending.sourceWebView.gestures
                   .recentGlanceOriginRect(maxAge: 2)
           ) {
            pending.sourceWebView.gestures.clear(
                ifCurrent: pending.childRequest.gestureReceipt
            )
            return webView
        }
        return childSurfaceRouter.open(pending.childRequest)
    }
}
