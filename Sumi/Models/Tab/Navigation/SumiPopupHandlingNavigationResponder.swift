import AppKit
import Common
import Foundation
import Navigation
import WebKit

@MainActor
final class SumiPopupHandlingNavigationResponder: NavigationResponder {
    private weak var tab: Tab?
    private var onNewWindow: ((WKNavigationAction) -> SumiNewWindowPolicy?)?

    init(tab: Tab) {
        self.tab = tab
    }

    func createWebView(
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
           browserManager.extensionManager.consumeRecentlyOpenedExtensionTabRequest(for: requestURL) {
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

        if let policy = newWindowPolicy(for: navigationAction) {
            return createChildWebView(
                from: webView,
                with: configuration,
                for: navigationAction,
                policy: policy,
                isExtensionOriginated: isExtensionOriginated
            )
        }

        let behavior = SumiLinkOpenBehavior(
            event: NSApp.currentEvent,
            switchToNewTabWhenOpenedPreference: false,
            canOpenLinkInCurrentTab: false,
            shouldSelectNewTab: true
        )
        let policy = SumiNewWindowPolicy(
            windowFeatures,
            linkOpenBehavior: behavior,
            preferTabsToWindows: true
        ).preferringSelectedTabs(true)

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
        guard let tab else { return .next }

        if tab.isPopupHost, isSumiInternalURL(navigationAction.url) {
            return .cancel
        }

        guard let targetFrame = navigationAction.targetFrame else { return .next }

        let isLinkActivated = !navigationAction.isTargetingNewWindow
            && (navigationAction.navigationType.isLinkActivated
                || (navigationAction.navigationType == .other && navigationAction.isUserInitiated))
        guard isLinkActivated else { return .next }

        if tab.isGlanceTriggerActive(navigationAction.modifierFlags) {
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
            modifierFlags: navigationAction.modifierFlags,
            switchToNewTabWhenOpenedPreference: false,
            canOpenLinkInCurrentTab: canOpenLinkInCurrentTab
        )

        switch behavior {
        case .currentTab:
            return .next
        case .newTab, .newWindow:
            let url = navigationAction.url
            onNewWindow = { newWindowNavigationAction in
                guard newWindowNavigationAction.request.url?.matches(url) ?? false else {
                    return nil
                }
                return behavior.newWindowPolicy()
            }
            targetFrame.webView?.sumiLoadInNewWindow(url)
            return .cancel
        }
    }

    private func newWindowPolicy(for navigationAction: WKNavigationAction) -> SumiNewWindowPolicy? {
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

        let childTab = browserManager.createPopupTab(
            from: tab,
            webViewConfigurationOverride: configuration,
            activate: policy.shouldActivateTab
        )
        let childWebView = FocusableWKWebView(frame: .zero, configuration: configuration)
        childWebView.uiDelegate = childTab
        childWebView.allowsBackForwardNavigationGestures = true
        childWebView.allowsMagnification = true
        childWebView.owningTab = childTab

        childTab.adoptPopupWebView(childWebView)
        if isExtensionOriginated {
            browserManager.extensionManager.prepareWebViewForExtensionRuntime(
                childWebView,
                currentURL: navigationAction.request.url,
                reason: "SumiPopupHandlingNavigationResponder.createChildWebView"
            )
        }

        SumiUserAgent.apply(to: childWebView)
        childWebView.configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        childWebView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        return childWebView
    }

    private func isSumiInternalURL(_ url: URL) -> Bool {
        SumiSurface.isSettingsSurfaceURL(url)
            || SumiSurface.isHistorySurfaceURL(url)
            || SumiSurface.isBookmarksSurfaceURL(url)
    }
}
