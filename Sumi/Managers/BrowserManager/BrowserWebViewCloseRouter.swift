import WebKit

/// Routes generic WebKit `webViewDidClose` events to glance or normal tracked
/// Tabs. Auxiliary WebViews close exclusively through their receipt-bound
/// `AuxiliaryWindowUIDelegate`.
@MainActor
final class BrowserWebViewCloseRouter {
    private let glanceHandleWebViewDidClose: @MainActor (WKWebView) -> Bool
    private let teardownAuxiliarySessionForTab:
        @MainActor (Tab, AuxiliaryWindowCloseReason) -> Bool
    private let isAuxiliaryMiniWindowTab: @MainActor (Tab) -> Bool
    private let removeAuxiliaryMiniWindowTab: @MainActor (Tab) -> Void
    private let notifyExtensionTabClosedAction: @MainActor (Tab) -> Void
    private let closeNormalWebView: @MainActor (WKWebView) -> Bool

    init(
        glanceHandleWebViewDidClose: @escaping @MainActor (WKWebView) -> Bool,
        teardownAuxiliarySessionForTab: @escaping @MainActor (
            Tab,
            AuxiliaryWindowCloseReason
        ) -> Bool,
        isAuxiliaryMiniWindowTab: @escaping @MainActor (Tab) -> Bool,
        removeAuxiliaryMiniWindowTab: @escaping @MainActor (Tab) -> Void,
        notifyExtensionTabClosed: @escaping @MainActor (Tab) -> Void,
        closeNormalWebView: @escaping @MainActor (WKWebView) -> Bool
    ) {
        self.glanceHandleWebViewDidClose = glanceHandleWebViewDidClose
        self.teardownAuxiliarySessionForTab =
            teardownAuxiliarySessionForTab
        self.isAuxiliaryMiniWindowTab = isAuxiliaryMiniWindowTab
        self.removeAuxiliaryMiniWindowTab = removeAuxiliaryMiniWindowTab
        self.notifyExtensionTabClosedAction = notifyExtensionTabClosed
        self.closeNormalWebView = closeNormalWebView
    }

    convenience init(browserManager: BrowserManager) {
        let webViewLifecycle = browserManager.webViewRuntime.lifecycleService
        let ownershipQuery = browserManager.webViewRuntime.ownershipQuery
        let targetResolver = WebKitCloseTargetResolver(
            lifecycle: webViewLifecycle,
            ownership: ownershipQuery,
            tabs: browserManager.tabManager,
            windowTabs: browserManager.shellRuntime.windowTabs,
            routing: browserManager.webViewRoutingService,
            registry: { [weak browserManager] in
                browserManager?.windowRegistry
            }
        )
        let childWindows = WebKitChildWindowCloseTransaction(
            lifecycle: webViewLifecycle,
            ownership: ownershipQuery,
            tabs: browserManager.tabManager,
            windowTabs: browserManager.shellRuntime.windowTabs,
            windowCommands: browserManager.windowCommands,
            registry: { [weak browserManager] in
                browserManager?.windowRegistry
            }
        )
        let closeCommands = BrowserWebKitCloseCommands(
            lifecycle: webViewLifecycle,
            tabClose: browserManager.tabLifecycleService.closeOrchestration,
            tabs: browserManager.tabManager
        )
        let normalClose = BrowserTabWebKitCloseService(
            targets: targetResolver,
            childWindows: childWindows,
            commands: closeCommands
        )
        self.init(
            glanceHandleWebViewDidClose: { [weak browserManager] webView in
                browserManager?.glanceManager.handleWebViewDidClose(webView) ?? false
            },
            teardownAuxiliarySessionForTab: {
                [weak browserManager] tab, reason in
                guard let auxiliaryWindows = browserManager?.auxiliaryWindows,
                      let session = auxiliaryWindows.sessions.session(
                          for: tab
                      ),
                      session.tab === tab,
                      let receipt = auxiliaryWindows.sessions.receipt(
                          for: session
                      ) else { return false }
                auxiliaryWindows.teardown.teardown(receipt, reason: reason)
                return true
            },
            isAuxiliaryMiniWindowTab: { [weak browserManager] tab in
                browserManager?.tabManager.transientWebKitTabLifecycleOwner.isAuxiliaryMiniWindowTab(tab) ?? false
            },
            removeAuxiliaryMiniWindowTab: { [weak browserManager] tab in
                browserManager?.tabManager.transientWebKitTabLifecycleOwner.removeAuxiliaryMiniWindowTab(tab)
            },
            notifyExtensionTabClosed: { [weak browserManager] tab in
                browserManager?.optionalModules.extensions.notifyTabClosedIfLoaded(tab)
            },
            closeNormalWebView: { [normalClose] webView in
                normalClose.handleWebViewDidClose(webView)
            }
        )
    }

    @discardableResult
    func handleWebViewDidClose(_ webView: WKWebView) -> Bool {
        if glanceHandleWebViewDidClose(webView) {
            return true
        }

        return handleNormalWebViewDidClose(webView)
    }

    @discardableResult
    func handleNormalWebViewDidClose(_ webView: WKWebView) -> Bool {
        closeNormalWebView(webView)
    }

    func closeAuxiliaryMiniWindow(
        for tab: Tab,
        reason: AuxiliaryWindowCloseReason = .extensionRequestedClose
    ) {
        guard isAuxiliaryMiniWindowTab(tab) else { return }

        if teardownAuxiliarySessionForTab(tab, reason) {
            return
        }

        removeAuxiliaryMiniWindowTab(tab)
        notifyExtensionTabClosedAction(tab)
    }

    /// Test seam for lazy-extension wiring checks that previously reached into Dependencies.
    func notifyExtensionTabClosed(_ tab: Tab) {
        notifyExtensionTabClosedAction(tab)
    }
}
