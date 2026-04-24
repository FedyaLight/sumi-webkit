import Foundation
import Navigation
import WebKit

@MainActor
final class SumiTabScriptAttachmentNavigationResponder: NavigationResponder {
    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
    }

    func decidePolicy(
        for navigationAction: NavigationAction,
        preferences _: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.scriptAttachmentResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.scriptAttachmentResponder", signpostState)
        }

        guard navigationAction.isForMainFrame,
              let tab,
              let webView = navigationAction.targetFrame?.webView ?? navigationAction.sourceFrame.webView
        else { return .next }

        await tab.replaceNormalTabUserScripts(
            on: webView.configuration.userContentController,
            for: navigationAction.url
        )
        return .next
    }
}
