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

        let didPresent = sourceTab.linkPresentationCommands.presentInGlance(
            url,
            from: sourceWebView,
            originRectInWindow: sourceWebView.gestures
                .recentGlanceOriginRect(maxAge: 2)
        )
        if didPresent {
            sourceWebView.consumeGestureForBrowserCommand()
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
    private let extensionRequests: (any ExtensionPopupRequestConsuming)?
    private let extensionTabs: (any ExtensionExternalTabOpening)?
    private let webPopups: (any PhysicalWebPopupOpening)?
    private let childTabs: (any WebKitChildTabOpening)?
    private let childWindows: (any WebKitChildWindowOpening)?

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
        self.extensionRequests = extensionRequests
        self.extensionTabs = extensionTabs
        self.webPopups = webPopups
        self.childTabs = childTabs
        self.childWindows = childWindows
    }

    func createWebView(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        createWebViewSynchronously(
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
        guard let tab,
              let sourceWebView = webView as? FocusableWKWebView,
              sourceWebView.owningTab === tab,
              tab.hasBrowserRuntime
        else { return nil }
        let gestureReceipt = sourceWebView.gestures.currentReceipt
        guard let sourceDocumentLease = tab.mainFrameDocumentLease(
            for: sourceWebView
        ) else {
            return nil
        }

        let sourceURL = exactSourceURL(
            for: navigationAction,
            sourceWebView: sourceWebView
        )
        let requestURL = navigationAction.request.url
        let isExtensionOriginated = SumiPopupNavigationOrigin.isExtensionOriginatedPopupNavigation(
            sourceURL: sourceURL,
            requestURL: requestURL
        )

        if let requestURL,
           SumiPopupNavigationOrigin.isExtensionOriginatedExternalPopupNavigation(sourceURL: sourceURL, requestURL: requestURL),
           extensionRequests?
            .consumeRecentlyOpenedExtensionTabRequestIfLoaded(
                for: requestURL
            ) == true {
            return nil
        }

        let navigationFlags = sourceWebView.gestures.resolvedModifierFlags(
            actionFlags: navigationAction.modifierFlags
        )
        if routeExplicitGlanceIfNeeded(
            requestURL,
            isRequested: tab.isGlanceTriggerActive(navigationFlags),
            tab: tab,
            sourceWebView: sourceWebView
        ) {
            return nil
        }

        let shouldOpenDynamicGlance = !isExtensionOriginated && (
            requestURL.map {
                tab.shouldOpenDynamicallyInGlance(url: $0, modifierFlags: navigationFlags)
            } ?? false
        )
        if routeDynamicGlanceIfNeeded(
            requestURL,
            isRequested: shouldOpenDynamicGlance,
            tab: tab,
            sourceWebView: sourceWebView,
            isExtensionOriginated: isExtensionOriginated
        ) {
            return nil
        }

        let behavior = SumiLinkOpenBehavior(
            buttonIsMiddle: navigationAction.buttonNumber == 2
                || sourceWebView.gestures.hasRecentAuxiliaryMouseDown,
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

        guard let tabContext = tab.popupPermissionTabContext(for: sourceWebView) else {
            return nil
        }
        let activationState = sourceWebView.popupUserActivation.claim(
            webKitUserInitiated: navigationAction.isUserInitiated
        )
        let request = SumiPopupPermissionRequest.fromWKNavigationAction(
            navigationAction,
            path: .uiDelegateCreateWebView,
            activationState: activationState,
            isExtensionOriginated: isExtensionOriginated
        )
        guard let permissions else { return nil }
        let permissionResult = await permissions.evaluate(
            request,
            tabContext: tabContext
        )
        guard permissionResult.isAllowed,
              sourceWebView.owningTab === tab,
              tab.mainFrameDocumentLease(for: sourceWebView)
                == sourceDocumentLease
        else {
            return nil
        }
        return createChildWebView(
            from: sourceWebView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures,
            policy: policy,
            isExtensionOriginated: isExtensionOriginated,
            gestureReceipt: gestureReceipt
        )
    }

    /// Same branch ordering as ``createWebViewAsync``.
    private func createWebViewSynchronously(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let tab,
              let sourceWebView = webView as? FocusableWKWebView,
              sourceWebView.owningTab === tab,
              tab.hasBrowserRuntime
        else { return nil }
        let gestureReceipt = sourceWebView.gestures.currentReceipt

        let sourceURL = exactSourceURL(
            for: navigationAction,
            sourceWebView: sourceWebView
        )
        let requestURL = navigationAction.request.url
        let isExtensionOriginated = SumiPopupNavigationOrigin.isExtensionOriginatedPopupNavigation(
            sourceURL: sourceURL,
            requestURL: requestURL
        )

        if let requestURL,
           SumiPopupNavigationOrigin.isExtensionOriginatedExternalPopupNavigation(sourceURL: sourceURL, requestURL: requestURL),
           extensionRequests?
            .consumeRecentlyOpenedExtensionTabRequestIfLoaded(
                for: requestURL
            ) == true {
            return nil
        }

        let navigationFlags = sourceWebView.gestures.resolvedModifierFlags(
            actionFlags: navigationAction.modifierFlags
        )
        if routeExplicitGlanceIfNeeded(
            requestURL,
            isRequested: tab.isGlanceTriggerActive(navigationFlags),
            tab: tab,
            sourceWebView: sourceWebView
        ) {
            return nil
        }

        let shouldOpenDynamicGlance = !isExtensionOriginated && (
            requestURL.map {
                tab.shouldOpenDynamicallyInGlance(url: $0, modifierFlags: navigationFlags)
            } ?? false
        )
        if routeDynamicGlanceIfNeeded(
            requestURL,
            isRequested: shouldOpenDynamicGlance,
            tab: tab,
            sourceWebView: sourceWebView,
            isExtensionOriginated: isExtensionOriginated
        ) {
            return nil
        }

        let behavior = SumiLinkOpenBehavior(
            buttonIsMiddle: navigationAction.buttonNumber == 2
                || sourceWebView.gestures.hasRecentAuxiliaryMouseDown,
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

        guard let tabContext = tab.popupPermissionTabContext(for: sourceWebView) else {
            return nil
        }
        let activationState = sourceWebView.popupUserActivation.claim(
            webKitUserInitiated: navigationAction.isUserInitiated
        )
        let request = SumiPopupPermissionRequest.fromWKNavigationAction(
            navigationAction,
            path: .uiDelegateCreateWebView,
            activationState: activationState,
            isExtensionOriginated: isExtensionOriginated
        )
        guard let permissions else { return nil }
        let permissionResult = permissions.evaluateSynchronouslyForWebKitFallback(
            request,
            tabContext: tabContext
        )
        guard permissionResult.isAllowed else { return nil }
        return createChildWebView(
            from: sourceWebView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures,
            policy: policy,
            isExtensionOriginated: isExtensionOriginated,
            gestureReceipt: gestureReceipt
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
           isSumiInternalURL(url) {
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
        guard let sourceTab = sourceWebView.owningTab else { return .next }
        if let targetWebView = targetWebView as? FocusableWKWebView {
            guard targetWebView.owningTab === targetTab else { return .next }
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
        if routeExplicitGlanceIfNeeded(
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
        if routeDynamicGlanceIfNeeded(
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
            guard targetTab.isPinned, navigationAction.isForMainFrame else {
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
            guard permissionResult.isAllowed else {
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

    private func routeExplicitGlanceIfNeeded(
        _ url: URL?,
        isRequested: Bool,
        tab: Tab,
        sourceWebView: FocusableWKWebView
    ) -> Bool {
        guard let url,
              url.sumiIsGlancePreviewableLink,
              isRequested
        else { return false }

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

    private func routeDynamicGlanceIfNeeded(
        _ url: URL?,
        isRequested: Bool,
        tab: Tab,
        sourceWebView: FocusableWKWebView,
        isExtensionOriginated: Bool,
        isMiddleButtonClick: Bool = false
    ) -> Bool {
        guard let url,
              !isExtensionOriginated,
              !isMiddleButtonClick,
              isRequested
        else { return false }

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

    private func createChildWebView(
        from webView: FocusableWKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures,
        policy: SumiNewWindowPolicy,
        isExtensionOriginated: Bool,
        gestureReceipt: WebViewGestureReceipt?
    ) -> WKWebView? {
        guard let tab,
              tab.hasBrowserRuntime
        else { return nil }

        if navigationAction.request.url?.sumiNavigationalScheme == .javascript {
            return nil
        }
        if policy.isPopup,
           let requestURL = navigationAction.request.url,
           isSumiInternalURL(requestURL) {
            return nil
        }

        let sourceURL = exactSourceURL(
            for: navigationAction,
            sourceWebView: webView
        )
        if let requestURL = navigationAction.request.url,
           SumiPopupNavigationOrigin.isExtensionOriginatedExternalPopupNavigation(
               sourceURL: sourceURL,
               requestURL: requestURL
            ) {
            if extensionTabs?.open(
                requestURL,
                from: webView
            ) == true {
                webView.gestures.clear(ifCurrent: gestureReceipt)
            }
            return nil
        }

        if policy.isPopup {
            let popupWebView = webPopups?.open(
                configuration: configuration,
                request: navigationAction.request,
                windowFeatures: windowFeatures,
                from: webView,
                isExtensionOriginated: isExtensionOriginated
            )
            if popupWebView != nil {
                webView.gestures.clear(ifCurrent: gestureReceipt)
            }
            return popupWebView
        }

        if case .window(let active) = policy {
            let childWebView = childWindows?.open(
                configuration: configuration,
                requestURL: navigationAction.request.url,
                from: webView,
                activate: active,
                isExtensionOriginated: isExtensionOriginated
            )
            if childWebView != nil {
                webView.gestures.clear(ifCurrent: gestureReceipt)
            }
            return childWebView
        }

        WebContentProcessDisplayNameProvider.apply(
            WebContentProcessDisplayNameProvider.popup,
            to: configuration
        )
        guard case .tab(let selected) = policy else {
            return nil
        }
        let childWebView = childTabs?.open(
            configuration: configuration,
            requestURL: navigationAction.request.url,
            from: webView,
            selected: selected,
            isExtensionOriginated: isExtensionOriginated
        )
        if childWebView != nil {
            webView.gestures.clear(ifCurrent: gestureReceipt)
        }
        return childWebView
    }

    private func exactSourceURL(
        for navigationAction: WKNavigationAction,
        sourceWebView: WKWebView
    ) -> URL? {
        navigationAction.sumiWebKitSourceURL
            ?? sourceWebView.committedURL
            ?? sourceWebView.url
    }

    private func isSumiInternalURL(_ url: URL) -> Bool {
        SumiSurface.isSettingsSurfaceURL(url)
            || SumiSurface.isHistorySurfaceURL(url)
            || SumiSurface.isBookmarksSurfaceURL(url)
    }
}

private extension SumiNavigationAction {
    var isNativeGlanceLinkActivation: Bool {
        navigationType.isLinkActivated
            || (navigationType == .other && isUserInitiated)
    }
}
