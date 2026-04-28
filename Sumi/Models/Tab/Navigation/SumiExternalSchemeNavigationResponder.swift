import AppKit
import Foundation
import Navigation
import WebKit

@MainActor
final class SumiExternalSchemeNavigationResponder: NavigationResponder {
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
        for navigationAction: NavigationAction,
        preferences _: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.externalSchemeResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.externalSchemeResponder", signpostState)
        }

        let externalURL = navigationAction.url
        guard externalURL.sumiIsExternalSchemeLink,
              SumiExternalSchemePermissionRequest.isValidExternalSchemeURL(externalURL)
        else {
            if navigationAction.isForMainFrame,
               navigationAction.redirectHistory?.isEmpty == false {
                shouldCloseTabOnExternalAppOpen = false
            }
            return .next
        }

        if let mainFrameNavigationAction = navigationAction.mainFrameNavigation?.navigationAction,
           (mainFrameNavigationAction.redirectHistory?.first ?? mainFrameNavigationAction).sumiIsUserEnteredURL {
            shouldCloseTabOnExternalAppOpen = false
        }

        defer {
            if navigationAction.isForMainFrame {
                shouldCloseTabOnExternalAppOpen = false
            }
        }

        let initialRequest = navigationAction.mainFrameNavigation?.navigationAction.redirectHistory?.first?.request
            ?? navigationAction.mainFrameNavigation?.navigationAction.request
            ?? navigationAction.request
        if [.returnCacheDataElseLoad, .returnCacheDataDontLoad].contains(initialRequest.cachePolicy) {
            return .cancel
        }

        guard let tab,
              let bridge = permissionBridge ?? tab.browserManager?.externalSchemePermissionBridge,
              let webView = navigationAction.targetFrame?.webView ?? navigationAction.sourceFrame.webView,
              let tabContext = tabContextProvider?(webView) ?? tab.externalSchemePermissionTabContext(for: webView)
        else {
            return .cancel
        }

        let request = SumiExternalSchemePermissionRequest.fromNavigationAction(navigationAction)
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

    func navigationDidFinish(_: Navigation) {
        shouldCloseTabOnExternalAppOpen = false
    }

    func navigation(_: Navigation, didFailWith error: WKError) {
        shouldCloseTabOnExternalAppOpen = false
    }
}
