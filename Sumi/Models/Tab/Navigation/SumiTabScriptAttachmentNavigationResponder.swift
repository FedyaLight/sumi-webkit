import Foundation
import SumiDomain
import WebKit

@MainActor
final class SumiTabScriptAttachmentNavigationResponder: SumiNavigationActionTargetWebViewResponding {
    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        targetWebView: WKWebView?,
        preferences: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        guard navigationAction.isForMainFrame,
              let tab,
              let targetWebView
        else { return .next }

        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.scriptAttachmentResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.scriptAttachmentResponder", signpostState)
        }

        await tab.replaceNormalTabUserScripts(
            on: targetWebView.configuration.userContentController,
            for: navigationAction.url
        )
        return .next
    }
}
