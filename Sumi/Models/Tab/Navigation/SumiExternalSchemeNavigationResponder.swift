import AppKit
import Foundation
import WebKit

@MainActor
final class SumiExternalSchemeNavigationResponder: SumiNavigationActionWebViewResponding, SumiNavigationCompletionResponding {
    typealias TabContextProvider = @MainActor (WKWebView) -> SumiExternalSchemePermissionTabContext?

    private weak var tab: Tab?
    private let permissionBridge: SumiExternalSchemePermissionBridge?
    private let tabContextProvider: TabContextProvider?
    private var shouldCloseTabOnExternalAppOpen = true

    init(
        tab: Tab,
        permissionBridge: SumiExternalSchemePermissionBridge? = nil,
        tabContextProvider: TabContextProvider? = nil
    ) {
        self.tab = tab
        self.permissionBridge = permissionBridge
        self.tabContextProvider = tabContextProvider
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        webView: WKWebView?,
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.externalSchemeResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.externalSchemeResponder", signpostState)
        }

        guard let externalURL = navigationAction.url,
              externalURL.sumiIsExternalSchemeLink,
              SumiExternalSchemePermissionRequest.isValidExternalSchemeURL(externalURL)
        else {
            if navigationAction.isForMainFrame,
               !navigationAction.redirectHistory.isEmpty {
                shouldCloseTabOnExternalAppOpen = false
            }
            return .next
        }

        if let mainFrameNavigation = navigationAction.mainFrameNavigation,
           (mainFrameNavigation.redirectHistory.first ?? mainFrameNavigation.navigationAction).isUserEnteredURL {
            shouldCloseTabOnExternalAppOpen = false
        }

        defer {
            if navigationAction.isForMainFrame {
                shouldCloseTabOnExternalAppOpen = false
            }
        }

        let initialRequest = navigationAction.mainFrameNavigation?.redirectHistory.first?.request
            ?? navigationAction.mainFrameNavigation?.navigationAction.request
            ?? navigationAction.request
        if [.returnCacheDataElseLoad, .returnCacheDataDontLoad].contains(initialRequest.cachePolicy) {
            return .cancel
        }

        guard let tab,
              let bridge = permissionBridge ?? tab.browserManager?.externalSchemePermissionBridge,
              let webView,
              let tabContext = tabContextProvider?(webView) ?? tab.externalSchemePermissionTabContext(for: webView)
        else {
            return .cancel
        }

        let request = SumiExternalSchemePermissionRequest.fromSumiNavigationAction(navigationAction)
        let result = await bridge.evaluate(
            request,
            tabContext: tabContext,
            willOpen: {
                webView.window?.makeFirstResponder(nil)
            }
        )

        if result.didOpen,
           shouldCloseTabOnExternalAppOpen {
            webView.sumiCloseWindow()
        }

        return .cancel
    }

    func navigationDidFinish() {
        shouldCloseTabOnExternalAppOpen = false
    }

    func navigationDidFail() {
        shouldCloseTabOnExternalAppOpen = false
    }
}
