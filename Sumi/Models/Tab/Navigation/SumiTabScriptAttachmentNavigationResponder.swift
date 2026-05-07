import Foundation
import WebKit

@MainActor
final class SumiTabScriptAttachmentNavigationResponder: SumiNavigationActionWebViewResponding {
    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        webView: WKWebView?,
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.scriptAttachmentResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.scriptAttachmentResponder", signpostState)
        }

        guard navigationAction.isForMainFrame,
              let tab,
              let webView
        else { return .next }

        await tab.replaceNormalTabUserScripts(
            on: webView.configuration.userContentController,
            for: navigationAction.url
        )
        return .next
    }
}
