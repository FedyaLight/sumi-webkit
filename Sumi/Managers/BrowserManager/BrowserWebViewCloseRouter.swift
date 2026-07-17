import WebKit

/// Routes generic WebKit `webViewDidClose` events to glance or normal tracked
/// Tabs. Auxiliary WebViews close exclusively through their receipt-bound
/// `AuxiliaryWindowUIDelegate`.
@MainActor
final class BrowserWebViewCloseRouter {
    private let glance: GlanceManager
    private let auxiliaryWindows: BrowserAuxiliaryWindowComposition
    private let auxiliaryTabs: AuxiliaryMiniWindowTabLifecycleTransaction
    private let extensions: SumiExtensionsModule
    private let normalClose: BrowserTabWebKitCloseService

    init(
        glance: GlanceManager,
        auxiliaryWindows: BrowserAuxiliaryWindowComposition,
        auxiliaryTabs: AuxiliaryMiniWindowTabLifecycleTransaction,
        extensions: SumiExtensionsModule,
        normalClose: BrowserTabWebKitCloseService
    ) {
        self.glance = glance
        self.auxiliaryWindows = auxiliaryWindows
        self.auxiliaryTabs = auxiliaryTabs
        self.extensions = extensions
        self.normalClose = normalClose
    }

    @discardableResult
    func handleWebViewDidClose(_ webView: WKWebView) -> Bool {
        if glance.handleWebViewDidClose(webView) {
            return true
        }

        return handleNormalWebViewDidClose(webView)
    }

    @discardableResult
    func handleNormalWebViewDidClose(_ webView: WKWebView) -> Bool {
        normalClose.handleWebViewDidClose(webView)
    }

    func closeAuxiliaryMiniWindow(
        for tab: Tab,
        reason: AuxiliaryWindowCloseReason = .extensionRequestedClose
    ) {
        guard auxiliaryTabs.containsExact(tab) else { return }

        if let session = auxiliaryWindows.sessions.session(for: tab),
           session.tab === tab,
           let receipt = auxiliaryWindows.sessions.receipt(for: session) {
            auxiliaryWindows.teardown.teardown(receipt, reason: reason)
            return
        }

        auxiliaryTabs.remove(tab)
        extensions.notifyTabClosedIfLoaded(tab)
    }
}
