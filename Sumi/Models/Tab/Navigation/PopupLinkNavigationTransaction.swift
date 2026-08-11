import AppKit
import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit

/// Admits and presents a link that policy has classified as a new browser
/// surface. Permission and exact-document evidence are revalidated before the
/// presentation is committed.
@MainActor
final class PopupLinkNavigationTransaction {
    private weak var tab: Tab?
    private let permissions: (any PopupPermissionEvaluating)?
    private let automaticGlance: (any AutomaticGlanceOpening)?

    init(
        tab: Tab,
        permissions: (any PopupPermissionEvaluating)?,
        automaticGlance: (any AutomaticGlanceOpening)?
    ) {
        self.tab = tab
        self.permissions = permissions
        self.automaticGlance = automaticGlance
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        sourceWebView: WKWebView?,
        targetWebView: WKWebView?,
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        guard let targetTab = tab, targetTab.hasBrowserRuntime else {
            return .next
        }

        if let url = navigationAction.url,
           targetTab.isPopupHost,
           SumiSurface.isNativeSurfaceURL(url) {
            return .cancel
        }
        guard let url = navigationAction.url else { return .next }

        let isLinkActivated = !navigationAction.isTargetingNewWindow
            && (navigationAction.navigationType.isLinkActivated
                || (navigationAction.navigationType == .other
                    && navigationAction.isUserInitiated))
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

        let signpostState = PerformanceTrace.beginInterval(
            "NavigationPolicy.popupResponder"
        )
        defer {
            PerformanceTrace.endInterval(
                "NavigationPolicy.popupResponder",
                signpostState
            )
        }

        let modifierFlags = sourceWebView.gestures.resolvedModifierFlags(
            actionFlags: navigationAction.modifierFlags
        )
        let isActiveGlancePreview = sourceTab.navigationRuntime.permissionRuntime
            .isActiveGlancePreviewSurface(sourceTab.id, sourceWebView)
        if LinkGlanceRouting.routeExplicit(
            url,
            isRequested: !isActiveGlancePreview
                && sourceTab.isGlanceTriggerActive(modifierFlags),
            tab: sourceTab,
            sourceWebView: sourceWebView
        ) {
            return .cancel
        }

        guard let targetFrame = navigationAction.targetFrame else { return .next }
        guard navigationAction.shouldDownload == false else { return .next }
        guard url.sumiIsExternalSchemeLink == false,
              url.sumiNavigationalScheme != .javascript
        else { return .next }

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
            return destinationHost == targetHost
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
            return await presentNewSurface(
                url,
                behavior: behavior,
                navigationAction: navigationAction,
                sourceTab: sourceTab,
                targetTab: targetTab,
                sourceWebView: sourceWebView,
                exactTargetWebView: exactTargetWebView,
                sourceDocumentLease: sourceDocumentLease,
                modifierFlags: modifierFlags,
                gestureReceipt: gestureReceipt
            )
        }
    }

    private func presentNewSurface(
        _ url: URL,
        behavior: SumiLinkOpenBehavior,
        navigationAction: SumiNavigationAction,
        sourceTab: Tab,
        targetTab: Tab,
        sourceWebView: FocusableWKWebView,
        exactTargetWebView: FocusableWKWebView?,
        sourceDocumentLease: TabMainFrameDocumentLease,
        modifierFlags: NSEvent.ModifierFlags,
        gestureReceipt: WebViewGestureReceipt?
    ) async -> SumiNavigationActionPolicy? {
        guard let tabContext = sourceTab.popupPermissionTabContext(
            for: sourceWebView
        ) else {
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
              sourceTab.committedDocumentRuntime.lease(for: sourceWebView)
                == sourceDocumentLease,
              tabContext.isCurrentPage(),
              exactTargetWebView?.owningTab === targetTab
                || (exactTargetWebView == nil && sourceTab === targetTab)
        else {
            return .cancel
        }

        let disposition: TabLinkDisposition
        switch behavior {
        case .currentTab:
            preconditionFailure(
                "Current-tab behavior returned from a new-surface branch"
            )
        case .newTab(let selected):
            disposition = .newTab(selected: selected)
        case .newWindow(let selected):
            disposition = .newWindow(selected: selected)
        }
        let isExtensionOriginated = SumiPopupNavigationOrigin
            .isExtensionOriginatedPopupNavigation(
                sourceURL: navigationAction.sourceURL
                    ?? sourceWebView.committedURL
                    ?? sourceWebView.url,
                requestURL: url
            )
        if AutomaticGlancePolicy.shouldPresent(
            url,
            from: sourceTab,
            ordinaryBehavior: behavior,
            modifierFlags: modifierFlags,
            isExtensionOriginated: isExtensionOriginated,
            isMiddleButtonClick: navigationAction.navigationType
                .isMiddleButtonClick,
            shouldDownload: navigationAction.shouldDownload
        ),
           automaticGlance?.openBrowserTab(
               url,
               from: sourceWebView,
               originRectInWindow: sourceWebView.gestures
                   .recentGlanceOriginRect(maxAge: 2)
           ) == true {
            sourceWebView.gestures.clear(ifCurrent: gestureReceipt)
            return .cancel
        }
        guard sourceTab.linkPresentationCommands.open(
            url,
            from: sourceWebView,
            disposition: disposition
        ) else {
            return .next
        }
        sourceWebView.gestures.clear(ifCurrent: gestureReceipt)
        return .cancel
    }
}
