import SumiWebRuntime
import WebKit

/// Ordinary Tab/WebView close commands used after physical target resolution.
/// Dedicated WebKit child shells are handled by their own transaction.
@MainActor
final class BrowserWebKitCloseCommands: BrowserWebKitCloseCommanding {
    private let lifecycle: WebViewLifecycleService
    private let tabClose: BrowserTabCloseOrchestrationOwner
    private let tabClosure: TabClosureService

    init(
        lifecycle: WebViewLifecycleService,
        tabClose: BrowserTabCloseOrchestrationOwner,
        tabClosure: TabClosureService
    ) {
        self.lifecycle = lifecycle
        self.tabClose = tabClose
        self.tabClosure = tabClosure
    }

    func closeTrackedTab(_ target: TrackedWebKitCloseTarget) {
        tabClose.closeTab(target.tab, in: target.window)
    }

    func closeUntrackedTab(_ target: UntrackedWebKitCloseTarget) {
        if let window = target.window {
            tabClose.closeTab(target.tab, in: window)
            return
        }
        target.tab.performComprehensiveWebViewCleanup()
        tabClosure.removeTab(target.tab.id)
    }

    func discardStaleTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) {
        lifecycle.cleanupTrackedWebViewAfterWebKitClose(
            webView,
            owner: owner
        )
    }

    func discardOrphanWebView(_ webView: WKWebView) {
        SumiAuxiliaryWebViewShutdown.perform(on: webView)
    }
}
