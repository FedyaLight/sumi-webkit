import WebKit

/// Routes WebKit `webViewDidClose` events to the surface that owns the WebView
/// (glance preview, auxiliary window, or a normal tracked tab) and tears down
/// auxiliary mini-window tabs.
@MainActor
final class BrowserWebViewCloseRouter {
    private let glanceHandleWebViewDidClose: @MainActor (WKWebView) -> Bool
    private let auxiliaryContains: @MainActor (WKWebView) -> Bool
    private let auxiliaryTeardown: @MainActor (WKWebView, AuxiliaryWindowCloseReason) -> Void
    private let auxiliarySessionWebView: @MainActor (Tab) -> WKWebView?
    private let isAuxiliaryMiniWindowTab: @MainActor (Tab) -> Bool
    private let removeAuxiliaryMiniWindowTab: @MainActor (Tab) -> Void
    private let notifyExtensionTabClosedAction: @MainActor (Tab) -> Void
    private let makeWebKitCloseRoutingRuntime: @MainActor () -> BrowserWebKitCloseRoutingOwner.Runtime

    init(
        glanceHandleWebViewDidClose: @escaping @MainActor (WKWebView) -> Bool,
        auxiliaryContains: @escaping @MainActor (WKWebView) -> Bool,
        auxiliaryTeardown: @escaping @MainActor (WKWebView, AuxiliaryWindowCloseReason) -> Void,
        auxiliarySessionWebView: @escaping @MainActor (Tab) -> WKWebView?,
        isAuxiliaryMiniWindowTab: @escaping @MainActor (Tab) -> Bool,
        removeAuxiliaryMiniWindowTab: @escaping @MainActor (Tab) -> Void,
        notifyExtensionTabClosed: @escaping @MainActor (Tab) -> Void,
        makeWebKitCloseRoutingRuntime: @escaping @MainActor () -> BrowserWebKitCloseRoutingOwner.Runtime
    ) {
        self.glanceHandleWebViewDidClose = glanceHandleWebViewDidClose
        self.auxiliaryContains = auxiliaryContains
        self.auxiliaryTeardown = auxiliaryTeardown
        self.auxiliarySessionWebView = auxiliarySessionWebView
        self.isAuxiliaryMiniWindowTab = isAuxiliaryMiniWindowTab
        self.removeAuxiliaryMiniWindowTab = removeAuxiliaryMiniWindowTab
        self.notifyExtensionTabClosedAction = notifyExtensionTabClosed
        self.makeWebKitCloseRoutingRuntime = makeWebKitCloseRoutingRuntime
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            glanceHandleWebViewDidClose: { [weak browserManager] webView in
                browserManager?.glanceManager.handleWebViewDidClose(webView) ?? false
            },
            auxiliaryContains: { [weak browserManager] webView in
                browserManager?.auxiliaryWindowManager.contains(webView: webView) ?? false
            },
            auxiliaryTeardown: { [weak browserManager] webView, reason in
                browserManager?.auxiliaryWindowManager.teardown(for: webView, reason: reason)
            },
            auxiliarySessionWebView: { [weak browserManager] tab in
                browserManager?.auxiliaryWindowManager.session(for: tab)?.webView
            },
            isAuxiliaryMiniWindowTab: { [weak browserManager] tab in
                browserManager?.tabManager.transientWebKitTabLifecycleOwner.isAuxiliaryMiniWindowTab(tab) ?? false
            },
            removeAuxiliaryMiniWindowTab: { [weak browserManager] tab in
                browserManager?.tabManager.transientWebKitTabLifecycleOwner.removeAuxiliaryMiniWindowTab(tab)
            },
            notifyExtensionTabClosed: { [weak browserManager] tab in
                browserManager?.extensionsModule.notifyTabClosedIfLoaded(tab)
            },
            makeWebKitCloseRoutingRuntime: { [weak browserManager] in
                BrowserWebKitCloseRoutingOwner.Runtime(
                    prepareClose: { [weak browserManager] webView in
                        browserManager?.shellRuntime.requireWebViewCoordinator().prepareWebKitClose(webView)
                            ?? .ready(trackedOwner: nil)
                    },
                    cleanupTrackedWebView: { [weak browserManager] webView, owner in
                        browserManager?.shellRuntime.requireWebViewCoordinator().cleanupTrackedWebViewAfterWebKitClose(
                            webView,
                            owner: owner
                        )
                    },
                    tab: { [weak browserManager] tabID in
                        browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabID)
                    },
                    regularTabs: { [weak browserManager] in
                        browserManager?.tabManager.tabCollectionMembershipOwner.allTabs() ?? []
                    },
                    allWindows: { [weak browserManager] in
                        browserManager?.windowRegistry?.allWindows ?? []
                    },
                    window: { [weak browserManager] windowID in
                        browserManager?.windowRegistry?.windows[windowID]
                    },
                    windowContaining: { [weak browserManager] tab in
                        browserManager?.windowTabContextOwner.windowState(containing: tab)
                    },
                    ownsLiveWebView: { [weak browserManager] webView, tab in
                        browserManager?.webViewRoutingService.ownsLiveWebView(webView, for: tab) ?? false
                    },
                    closeTab: { [weak browserManager] tab, windowState in
                        browserManager?.tabLifecycleService.closeOrchestration.closeTab(tab, in: windowState)
                    },
                    removeTab: { [weak browserManager] tabID in
                        browserManager?.tabManager.tabRemovalOwner.removeTab(tabID)
                    }
                )
            }
        )
    }

    @discardableResult
    func handleWebViewDidClose(_ webView: WKWebView) -> Bool {
        if glanceHandleWebViewDidClose(webView) {
            return true
        }

        if auxiliaryContains(webView) {
            auxiliaryTeardown(webView, .webViewDidClose)
            return true
        }

        return handleNormalWebViewDidClose(webView)
    }

    @discardableResult
    func handleNormalWebViewDidClose(_ webView: WKWebView) -> Bool {
        BrowserWebKitCloseRoutingOwner().handleWebViewDidClose(
            webView,
            runtime: makeWebKitCloseRoutingRuntime()
        )
    }

    func closeAuxiliaryMiniWindow(
        for tab: Tab,
        reason: AuxiliaryWindowCloseReason = .extensionRequestedClose
    ) {
        guard isAuxiliaryMiniWindowTab(tab) else { return }

        if let webView = auxiliarySessionWebView(tab) {
            auxiliaryTeardown(webView, reason)
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
