import AppKit
import Common
import Foundation
import Navigation
import WebKit

@MainActor
final class SumiPopupHandlingNavigationResponder: NavigationResponder {
    private struct PendingNewWindow {
        let policy: SumiNewWindowPolicy
        let permissionResult: SumiPopupPermissionResult
    }

    private weak var tab: Tab?
    private var onNewWindow: ((WKNavigationAction) -> PendingNewWindow?)?

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

    func createWebViewAsync(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) async -> WKWebView? {
        guard let tab,
              let browserManager = tab.browserManager
        else { return nil }

        let sourceURL = navigationAction.safeSourceFrame?.safeRequest?.url
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
        if let requestURL,
           !isExtensionOriginated,
           tab.isGlanceTriggerActive(navigationFlags) {
            tab.openURLInGlance(requestURL)
            return nil
        }

        if let requestURL,
           !isExtensionOriginated,
           tab.shouldRedirectToPeek(url: requestURL) {
            tab.openURLInGlance(requestURL)
            return nil
        }

        if let pendingNewWindow = newWindowPolicy(for: navigationAction) {
            return createChildWebView(
                from: webView,
                with: configuration,
                for: navigationAction,
                policy: pendingNewWindow.policy,
                isExtensionOriginated: isExtensionOriginated
            )
        }

        let behavior = SumiLinkOpenBehavior(
            buttonIsMiddle: false,
            modifierFlags: tab.navigationModifierFlags(from: navigationAction),
            switchToNewTabWhenOpenedPreference: false,
            canOpenLinkInCurrentTab: false,
            shouldSelectNewTab: true
        )
        let policy = SumiNewWindowPolicy(
            windowFeatures,
            linkOpenBehavior: behavior,
            preferTabsToWindows: true
        ).preferringSelectedTabs(true)

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
            policy: policy,
            isExtensionOriginated: isExtensionOriginated
        )
    }

    private func createWebViewSynchronously(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let tab,
              let browserManager = tab.browserManager
        else { return nil }

        let sourceURL = navigationAction.safeSourceFrame?.safeRequest?.url
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
        if let requestURL,
           !isExtensionOriginated,
           tab.isGlanceTriggerActive(navigationFlags) {
            tab.openURLInGlance(requestURL)
            return nil
        }

        if let requestURL,
           !isExtensionOriginated,
           tab.shouldRedirectToPeek(url: requestURL) {
            tab.openURLInGlance(requestURL)
            return nil
        }

        if let pendingNewWindow = newWindowPolicy(for: navigationAction) {
            return createChildWebView(
                from: webView,
                with: configuration,
                for: navigationAction,
                policy: pendingNewWindow.policy,
                isExtensionOriginated: isExtensionOriginated
            )
        }

        let behavior = SumiLinkOpenBehavior(
            buttonIsMiddle: false,
            modifierFlags: tab.navigationModifierFlags(from: navigationAction),
            switchToNewTabWhenOpenedPreference: false,
            canOpenLinkInCurrentTab: false,
            shouldSelectNewTab: true
        )
        let policy = SumiNewWindowPolicy(
            windowFeatures,
            linkOpenBehavior: behavior,
            preferTabsToWindows: true
        ).preferringSelectedTabs(true)

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
            policy: policy,
            isExtensionOriginated: isExtensionOriginated
        )
    }

    func willStart(_: Navigation) {
        onNewWindow = nil
    }

    func decidePolicy(
        for navigationAction: NavigationAction,
        preferences _: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.popupResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.popupResponder", signpostState)
        }

        guard let tab,
              let browserManager = tab.browserManager
        else { return .next }

        if tab.isPopupHost, isSumiInternalURL(navigationAction.url) {
            return .cancel
        }

        guard let targetFrame = navigationAction.targetFrame else { return .next }

        let isLinkActivated = !navigationAction.isTargetingNewWindow
            && (navigationAction.navigationType.isLinkActivated
                || (navigationAction.navigationType == .other && navigationAction.isUserInitiated))
        guard isLinkActivated else { return .next }

        let modifierFlags = tab.navigationModifierFlags(from: navigationAction)
        if tab.isGlanceTriggerActive(modifierFlags) {
            tab.openURLInGlance(navigationAction.url)
            return .cancel
        }

        let canOpenLinkInCurrentTab: Bool = {
            let navigatingToAnotherDomain = navigationAction.url.host != targetFrame.url.host && !targetFrame.url.isEmpty
            let navigatingAwayFromPinnedTab = tab.isPinned && navigatingToAnotherDomain && navigationAction.isForMainFrame
            return !navigatingAwayFromPinnedTab
        }()

        let behavior = SumiLinkOpenBehavior(
            buttonIsMiddle: navigationAction.navigationType.isMiddleButtonClick,
            modifierFlags: modifierFlags,
            switchToNewTabWhenOpenedPreference: false,
            canOpenLinkInCurrentTab: canOpenLinkInCurrentTab
        )

        switch behavior {
        case .currentTab:
            return .next
        case .newTab, .newWindow:
            let url = navigationAction.url
            guard let targetWebView = targetFrame.webView,
                  let tabContext = tab.popupPermissionTabContext(for: targetWebView)
            else {
                return .cancel
            }
            let activationState = tab.popupUserActivationTracker.activationState(
                webKitUserInitiated: nil,
                navigationActionUserInitiated: navigationAction.isUserInitiated
            )
            let request = SumiPopupPermissionRequest.fromNavigationAction(
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
            onNewWindow = { newWindowNavigationAction in
                guard newWindowNavigationAction.request.url?.matches(url) ?? false else {
                    return nil
                }
                return PendingNewWindow(policy: policy, permissionResult: permissionResult)
            }
            tab.clearWebViewInteractionEvent()
            targetWebView.sumiLoadInNewWindow(url)
            return .cancel
        }
    }

    private func newWindowPolicy(for navigationAction: WKNavigationAction) -> PendingNewWindow? {
        if let decision = onNewWindow?(navigationAction) {
            onNewWindow = nil
            return decision
        }
        return nil
    }

    private func createChildWebView(
        from _: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        policy: SumiNewWindowPolicy,
        isExtensionOriginated: Bool
    ) -> WKWebView? {
        guard let tab,
              let browserManager = tab.browserManager
        else { return nil }

        if navigationAction.request.url?.navigationalScheme == .javascript {
            return nil
        }
        if policy.isPopup,
           let requestURL = navigationAction.request.url,
           isSumiInternalURL(requestURL) {
            return nil
        }

        if let profile = explicitPopupOpenerProfile(for: tab, browserManager: browserManager) {
            SharedVisitedLinkStoreProvider.shared.applyStore(
                to: configuration,
                for: profile
            )
        }

        let childTab = browserManager.createPopupTab(
            from: tab,
            activate: policy.shouldActivateTab
        )
        return childTab.createPopupWebViewFromWebKitConfiguration(
            configuration,
            currentURL: navigationAction.request.url,
            isExtensionOriginated: isExtensionOriginated,
            reason: "SumiPopupHandlingNavigationResponder.createChildWebView"
        )
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
