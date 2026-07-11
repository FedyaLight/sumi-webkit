import SumiWebRuntime
import WebKit

/// Ordinary Tab/WebView close commands used after physical target resolution.
/// Dedicated WebKit child shells are handled by their own transaction.
@MainActor
final class BrowserWebKitCloseCommands: BrowserWebKitCloseCommanding {
    private weak var lifecycle: WebViewLifecycleService?
    private weak var tabClose: BrowserTabCloseOrchestrationOwner?
    private weak var tabs: TabManager?

    init(
        lifecycle: WebViewLifecycleService,
        tabClose: BrowserTabCloseOrchestrationOwner,
        tabs: TabManager
    ) {
        self.lifecycle = lifecycle
        self.tabClose = tabClose
        self.tabs = tabs
    }

    func closeTrackedTab(_ target: TrackedWebKitCloseTarget) {
        tabClose?.closeTab(target.tab, in: target.window)
    }

    func closeUntrackedTab(_ target: UntrackedWebKitCloseTarget) {
        if let window = target.window {
            tabClose?.closeTab(target.tab, in: window)
            return
        }
        target.tab.performComprehensiveWebViewCleanup()
        tabs?.tabRemovalOwner.removeTab(target.tab.id)
    }

    func discardStaleTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) {
        lifecycle?.cleanupTrackedWebViewAfterWebKitClose(
            webView,
            owner: owner
        )
    }

    func discardOrphanWebView(_ webView: WKWebView) {
        SumiAuxiliaryWebViewShutdown.perform(on: webView)
    }
}
