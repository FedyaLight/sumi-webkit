import AppKit
import Foundation
import WebKit

@MainActor
final class SumiGlanceNavigationResponder: SumiNavigationActionWebViewResponding {
    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        webView _: WKWebView?,
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        guard let tab,
              tab.browserManager != nil,
              let url = navigationAction.url,
              url.sumiIsGlancePreviewableLink,
              navigationAction.isNativeGlanceLinkActivation
        else { return .next }

        let flags = navigationAction.modifierFlags.intersection([.command, .option, .control, .shift])
        let modifierFlags = tab.resolvedNavigationModifierFlags(actionFlags: flags)
        guard tab.isGlanceTriggerActive(modifierFlags) else { return .next }

        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.glanceResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.glanceResponder", signpostState)
        }

        tab.openURLInGlanceFromLinkGesture(url)
        tab.clearWebViewInteractionEvent()
        tab.setClickModifierFlags([])
        return .cancel
    }
}

@MainActor
final class SumiPopupHandlingNavigationResponder: SumiNavigationActionWebViewResponding, SumiNavigationStartResponding {
    private enum PendingNewWindow {
        case child(SumiNewWindowPolicy)
        case consumed
    }

    private weak var tab: Tab?
    private var onNewWindow: ((WKNavigationAction) -> PendingNewWindow?)?
    private var contextMenuRouteToken: UInt64?

    init(tab: Tab) {
        self.tab = tab
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
    /// Glance when explicitly triggered (Option) → pending `window.open` match → Zen-like essential external Glance → new tab/window.
    func createWebViewAsync(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) async -> WKWebView? {
        guard let tab,
              let browserManager = tab.browserManager
        else { return nil }

        let sourceURL = navigationAction.sumiWebKitSourceURL ?? webView.url ?? tab.url
        let requestURL = navigationAction.request.url
        let isExtensionOriginated = Tab.isExtensionOriginatedPopupNavigation(
            sourceURL: sourceURL,
            requestURL: requestURL
        )

        if let requestURL,
           Tab.isExtensionOriginatedExternalPopupNavigation(sourceURL: sourceURL, requestURL: requestURL),
           browserManager.extensionsModule.consumeRecentlyOpenedExtensionTabRequestIfLoaded(for: requestURL) {
            return nil
        }

        let navigationFlags = tab.navigationModifierFlags(from: navigationAction)
        if routeExplicitGlanceIfNeeded(
            requestURL,
            isRequested: tab.isGlanceTriggerActive(navigationFlags),
            tab: tab
        ) {
            return nil
        }

        if let pendingNewWindow = newWindowPolicy(for: navigationAction) {
            guard case .child(let policy) = pendingNewWindow else {
                resetLinkGestureModifierState(for: tab)
                return nil
            }
            return createChildWebView(
                from: webView,
                with: configuration,
                for: navigationAction,
                windowFeatures: windowFeatures,
                policy: policy,
                isExtensionOriginated: isExtensionOriginated
            )
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
            isExtensionOriginated: isExtensionOriginated
        ) {
            return nil
        }

        let behavior = SumiLinkOpenBehavior(
            buttonIsMiddle: false,
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

        guard let tabContext = tab.popupPermissionTabContext(for: webView) else { return nil }
        let activationState = tab.popupUserActivationTracker.activationState(
            webKitUserInitiated: navigationAction.isUserInitiated
        )
        let request = SumiPopupPermissionRequest.fromWKNavigationAction(
            navigationAction,
            path: .uiDelegateCreateWebView,
            activationState: activationState,
            isExtensionOriginated: isExtensionOriginated
        )
        let permissionResult = await browserManager.popupPermissionBridge.evaluate(
            request,
            tabContext: tabContext
        )
        guard permissionResult.isAllowed else { return nil }
        tab.popupUserActivationTracker.consumeIfUserActivated(request.userActivation)

        return createChildWebView(
            from: webView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures,
            policy: policy,
            isExtensionOriginated: isExtensionOriginated
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
              let browserManager = tab.browserManager
        else { return nil }

        let sourceURL = navigationAction.sumiWebKitSourceURL ?? webView.url ?? tab.url
        let requestURL = navigationAction.request.url
        let isExtensionOriginated = Tab.isExtensionOriginatedPopupNavigation(
            sourceURL: sourceURL,
            requestURL: requestURL
        )

        if let requestURL,
           Tab.isExtensionOriginatedExternalPopupNavigation(sourceURL: sourceURL, requestURL: requestURL),
           browserManager.extensionsModule.consumeRecentlyOpenedExtensionTabRequestIfLoaded(for: requestURL) {
            return nil
        }

        let navigationFlags = tab.navigationModifierFlags(from: navigationAction)
        if routeExplicitGlanceIfNeeded(
            requestURL,
            isRequested: tab.isGlanceTriggerActive(navigationFlags),
            tab: tab
        ) {
            return nil
        }

        if let pendingNewWindow = newWindowPolicy(for: navigationAction) {
            guard case .child(let policy) = pendingNewWindow else {
                resetLinkGestureModifierState(for: tab)
                return nil
            }
            return createChildWebView(
                from: webView,
                with: configuration,
                for: navigationAction,
                windowFeatures: windowFeatures,
                policy: policy,
                isExtensionOriginated: isExtensionOriginated
            )
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
            isExtensionOriginated: isExtensionOriginated
        ) {
            return nil
        }

        let behavior = SumiLinkOpenBehavior(
            buttonIsMiddle: false,
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

        guard let tabContext = tab.popupPermissionTabContext(for: webView) else { return nil }
        let activationState = tab.popupUserActivationTracker.activationState(
            webKitUserInitiated: navigationAction.isUserInitiated
        )
        let request = SumiPopupPermissionRequest.fromWKNavigationAction(
            navigationAction,
            path: .uiDelegateCreateWebView,
            activationState: activationState,
            isExtensionOriginated: isExtensionOriginated
        )
        let permissionResult = browserManager.popupPermissionBridge.evaluateSynchronouslyForWebKitFallback(
            request,
            tabContext: tabContext
        )
        guard permissionResult.isAllowed else { return nil }
        tab.popupUserActivationTracker.consumeIfUserActivated(request.userActivation)

        return createChildWebView(
            from: webView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures,
            policy: policy,
            isExtensionOriginated: isExtensionOriginated
        )
    }

    func navigationWillStart(_: SumiNavigationContext) {
        onNewWindow = nil
        contextMenuRouteToken = nil
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        webView targetWebView: WKWebView?,
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        guard let tab,
              let browserManager = tab.browserManager
        else { return .next }

        if let url = navigationAction.url,
           tab.isPopupHost,
           isSumiInternalURL(url) {
            return .cancel
        }

        guard let url = navigationAction.url else { return .next }

        let isLinkActivated = !navigationAction.isTargetingNewWindow
            && (navigationAction.navigationType.isLinkActivated
                || (navigationAction.navigationType == .other && navigationAction.isUserInitiated))
        guard isLinkActivated else { return .next }

        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.popupResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.popupResponder", signpostState)
        }

        let modifierFlags = navigationModifierFlags(from: navigationAction, tab: tab)
        if routeExplicitGlanceIfNeeded(
            url,
            isRequested: tab.isGlanceTriggerActive(modifierFlags),
            tab: tab
        ) {
            return .cancel
        }

        guard let targetFrame = navigationAction.targetFrame else { return .next }

        let isExtensionOriginated = Tab.isExtensionOriginatedPopupNavigation(
            sourceURL: navigationAction.sourceURL,
            requestURL: url
        )
        let isMiddleButtonClick = navigationAction.navigationType.isMiddleButtonClick
        let shouldOpenDynamicGlance = !isExtensionOriginated
            && !isMiddleButtonClick
            && tab.shouldOpenDynamicallyInGlance(
                url: url,
                modifierFlags: modifierFlags
            )
        if routeDynamicGlanceIfNeeded(
            url,
            isRequested: shouldOpenDynamicGlance,
            tab: tab,
            isExtensionOriginated: isExtensionOriginated,
            isMiddleButtonClick: isMiddleButtonClick
        ) {
            return .cancel
        }

        let canOpenLinkInCurrentTab: Bool = {
            let navigatingToAnotherDomain = url.host != targetFrame.url?.host && !(targetFrame.url?.sumiIsEmpty ?? true)
            let navigatingAwayFromPinnedTab = tab.isPinned && navigatingToAnotherDomain && navigationAction.isForMainFrame
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
            guard let targetWebView,
                  let tabContext = tab.popupPermissionTabContext(for: targetWebView)
            else {
                return .cancel
            }
            let activationState = tab.popupUserActivationTracker.activationState(
                webKitUserInitiated: nil,
                navigationActionUserInitiated: navigationAction.isUserInitiated
            )
            let request = SumiPopupPermissionRequest.fromSumiNavigationAction(
                navigationAction,
                activationState: activationState
            )
            let permissionResult = await browserManager.popupPermissionBridge.evaluate(
                request,
                tabContext: tabContext
            )
            guard permissionResult.isAllowed,
                  let policy = behavior.newWindowPolicy()
            else {
                return .cancel
            }
            tab.popupUserActivationTracker.consumeIfUserActivated(request.userActivation)
            contextMenuRouteToken = nil
            onNewWindow = { newWindowNavigationAction in
                guard newWindowNavigationAction.request.url?.matches(url) ?? false else {
                    return nil
                }
                return .child(policy)
            }
            resetLinkGestureModifierState(for: tab)
            targetWebView.sumiLoadInNewWindow(url)
            return .cancel
        }
    }

    private func navigationModifierFlags(
        from navigationAction: SumiNavigationAction,
        tab: Tab
    ) -> NSEvent.ModifierFlags {
        let flags = navigationAction.modifierFlags.intersection([.command, .option, .control, .shift])
        return tab.resolvedNavigationModifierFlags(actionFlags: flags)
    }

    private func newWindowPolicy(for navigationAction: WKNavigationAction) -> PendingNewWindow? {
        if let decision = onNewWindow?(navigationAction) {
            onNewWindow = nil
            contextMenuRouteToken = nil
            return decision
        }
        return nil
    }

    /// Native WebKit context items already know the exact URL under the pointer.
    /// Sumi consumes that one request and performs the browser command itself.
    @discardableResult
    func consumeNativeContextMenuRequest(
        from item: NSMenuItem,
        perform handler: @escaping @MainActor (WKNavigationAction) -> Void
    ) -> Bool {
        guard let action = item.action else { return false }

        let token = (contextMenuRouteToken ?? 0) &+ 1
        contextMenuRouteToken = token
        onNewWindow = { [weak self] navigationAction in
            self?.contextMenuRouteToken = nil
            handler(navigationAction)
            return .consumed
        }

        let didSendAction = NSApp.sendAction(action, to: item.target, from: item)
        guard didSendAction else {
            clearContextMenuRoute(token)
            return false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.clearContextMenuRoute(token)
        }
        return true
    }

    private func clearContextMenuRoute(_ token: UInt64) {
        guard contextMenuRouteToken == token else { return }
        onNewWindow = nil
        contextMenuRouteToken = nil
    }

    private func routeExplicitGlanceIfNeeded(
        _ url: URL?,
        isRequested: Bool,
        tab: Tab
    ) -> Bool {
        guard let url,
              url.sumiIsGlancePreviewableLink,
              isRequested
        else { return false }

        tab.openURLInGlanceFromLinkGesture(url)
        resetLinkGestureModifierState(for: tab)
        return true
    }

    private func routeDynamicGlanceIfNeeded(
        _ url: URL?,
        isRequested: Bool,
        tab: Tab,
        isExtensionOriginated: Bool,
        isMiddleButtonClick: Bool = false
    ) -> Bool {
        guard let url,
              !isExtensionOriginated,
              !isMiddleButtonClick,
              isRequested
        else { return false }

        tab.openURLInGlanceFromLinkGesture(url)
        resetLinkGestureModifierState(for: tab)
        return true
    }

    private func createChildWebView(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures,
        policy: SumiNewWindowPolicy,
        isExtensionOriginated: Bool
    ) -> WKWebView? {
        guard let tab,
              let browserManager = tab.browserManager
        else { return nil }

        if navigationAction.request.url?.sumiNavigationalScheme == .javascript {
            return nil
        }
        if policy.isPopup,
           let requestURL = navigationAction.request.url,
           isSumiInternalURL(requestURL) {
            return nil
        }

        let sourceURL = navigationAction.sumiWebKitSourceURL ?? webView.url ?? tab.url
        if let requestURL = navigationAction.request.url,
           Tab.isExtensionOriginatedExternalPopupNavigation(
               sourceURL: sourceURL,
               requestURL: requestURL
           )
        {
            let targetSpace = tab.spaceId.flatMap { spaceID in
                browserManager.tabManager.spaces.first(where: { $0.id == spaceID })
            } ?? browserManager.tabManager.currentSpace
            let childTab = browserManager.tabManager.createNewTab(
                url: requestURL.absoluteString,
                in: targetSpace,
                activate: true
            )
            if let windowState = browserManager.windowState(containing: tab) {
                browserManager.materializeVisibleTabWebViewIfNeeded(childTab, in: windowState)
                browserManager.selectTab(childTab, in: windowState, loadPolicy: .immediate)
            }
            if childTab.isUnloaded {
                childTab.loadWebViewIfNeeded()
            }
            browserManager.extensionsModule.registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
                childTab,
                reason: "SumiPopupHandlingNavigationResponder.extensionExternalTab"
            )
            resetLinkGestureModifierState(for: tab)
            return nil
        }

        if policy.isPopup {
            let popupWebView = browserManager.auxiliaryWindowManager.presentWebPopup(
                configuration: configuration,
                request: navigationAction.request,
                windowFeatures: windowFeatures,
                openerTab: tab,
                isExtensionOriginated: isExtensionOriginated,
                shouldActivateApp: true
            )
            resetLinkGestureModifierState(for: tab)
            return popupWebView
        }

        if let profile = explicitPopupOpenerProfile(for: tab, browserManager: browserManager) {
            SharedVisitedLinkStoreProvider.shared.applyStore(
                to: configuration,
                for: profile
            )
        }

        WebContentProcessDisplayNameProvider.apply(
            WebContentProcessDisplayNameProvider.popup,
            to: configuration
        )

        guard let childTab = browserManager.createPopupTab(
            from: tab,
            activate: policy.shouldActivateTab
        ) else { return nil }
        let childWebView = childTab.createPopupWebViewFromWebKitConfiguration(
            configuration,
            currentURL: navigationAction.request.url,
            isExtensionOriginated: isExtensionOriginated,
            reason: "SumiPopupHandlingNavigationResponder.createChildWebView"
        )
        if policy.shouldActivateTab,
           let windowState = browserManager.windowState(containing: tab) {
            browserManager.selectTab(childTab, in: windowState)
        }
        resetLinkGestureModifierState(for: tab)
        return childWebView
    }

    /// Clears AppKit/WebKit modifier snapshots on the opener after a link gesture opens another web view so later
    /// link navigations (Glance, Cmd+new tab, middle-click, etc.) resolve modifiers from a clean slate — same idea as after ``decidePolicy`` new-window loads.
    private func resetLinkGestureModifierState(for tab: Tab) {
        tab.clearWebViewInteractionEvent()
        tab.setClickModifierFlags([])
    }

    private func isSumiInternalURL(_ url: URL) -> Bool {
        SumiSurface.isSettingsSurfaceURL(url)
            || SumiSurface.isHistorySurfaceURL(url)
            || SumiSurface.isBookmarksSurfaceURL(url)
    }

    private func explicitPopupOpenerProfile(
        for tab: Tab,
        browserManager: BrowserManager
    ) -> Profile? {
        if let profileId = tab.profileId {
            if let windowState = browserManager.windowRegistry?.windows.values.first(where: { window in
                window.ephemeralTabs.contains(where: { $0.id == tab.id })
            }),
               let ephemeralProfile = windowState.ephemeralProfile,
               ephemeralProfile.id == profileId
            {
                return ephemeralProfile
            }

            return browserManager.profileManager.profiles.first { $0.id == profileId }
        }

        if let spaceId = tab.spaceId,
           let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId }),
           let profileId = space.profileId {
            return browserManager.profileManager.profiles.first { $0.id == profileId }
        }

        return nil
    }
}

private extension SumiNavigationAction {
    var isNativeGlanceLinkActivation: Bool {
        navigationType.isLinkActivated
            || (navigationType == .other && isUserInitiated)
    }
}
