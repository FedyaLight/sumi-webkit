import WebKit

/// Routes WebKit `webViewDidClose` events to the surface that owns the WebView
/// (glance preview, auxiliary window, or a normal tracked tab) and tears down
/// auxiliary mini-window tabs.
@MainActor
final class BrowserWebViewCloseRouter {
    struct Dependencies {
        let glanceHandleWebViewDidClose: @MainActor (WKWebView) -> Bool
        let auxiliaryContains: @MainActor (WKWebView) -> Bool
        let auxiliaryTeardown: @MainActor (WKWebView, AuxiliaryWindowCloseReason) -> Void
        let auxiliarySessionWebView: @MainActor (Tab) -> WKWebView?
        let isAuxiliaryMiniWindowTab: @MainActor (Tab) -> Bool
        let removeAuxiliaryMiniWindowTab: @MainActor (Tab) -> Void
        let notifyExtensionTabClosed: @MainActor (Tab) -> Void
        let makeWebKitCloseRoutingRuntime: @MainActor () -> BrowserWebKitCloseRoutingOwner.Runtime
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func handleWebViewDidClose(_ webView: WKWebView) -> Bool {
        if dependencies.glanceHandleWebViewDidClose(webView) {
            return true
        }

        if dependencies.auxiliaryContains(webView) {
            dependencies.auxiliaryTeardown(webView, .webViewDidClose)
            return true
        }

        return handleNormalWebViewDidClose(webView)
    }

    @discardableResult
    func handleNormalWebViewDidClose(_ webView: WKWebView) -> Bool {
        BrowserWebKitCloseRoutingOwner().handleWebViewDidClose(
            webView,
            runtime: dependencies.makeWebKitCloseRoutingRuntime()
        )
    }

    func closeAuxiliaryMiniWindow(
        for tab: Tab,
        reason: AuxiliaryWindowCloseReason = .extensionRequestedClose
    ) {
        guard dependencies.isAuxiliaryMiniWindowTab(tab) else { return }

        if let webView = dependencies.auxiliarySessionWebView(tab) {
            dependencies.auxiliaryTeardown(webView, reason)
            return
        }

        dependencies.removeAuxiliaryMiniWindowTab(tab)
        dependencies.notifyExtensionTabClosed(tab)
    }
}

extension BrowserWebViewCloseRouter.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
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
                browserManager?.tabManager.isAuxiliaryMiniWindowTab(tab) ?? false
            },
            removeAuxiliaryMiniWindowTab: { [weak browserManager] tab in
                browserManager?.tabManager.removeAuxiliaryMiniWindowTab(tab)
            },
            notifyExtensionTabClosed: { [weak browserManager] tab in
                guard let browserManager else { return }
                BrowserManagerRuntimeWiring.notifyExtensionTabClosed(tab, for: browserManager)
            },
            makeWebKitCloseRoutingRuntime: { [weak browserManager] in
                BrowserWebKitCloseRoutingOwner.Runtime(
                    prepareClose: { [weak browserManager] webView in
                        browserManager?.requireWebViewCoordinator().prepareWebKitClose(webView)
                            ?? .ready(trackedOwner: nil)
                    },
                    cleanupTrackedWebView: { [weak browserManager] webView, owner in
                        browserManager?.requireWebViewCoordinator().cleanupTrackedWebViewAfterWebKitClose(
                            webView,
                            owner: owner
                        )
                    },
                    tab: { [weak browserManager] tabID in
                        browserManager?.tabManager.tab(for: tabID)
                    },
                    regularTabs: { [weak browserManager] in
                        browserManager?.tabManager.allTabs() ?? []
                    },
                    allWindows: { [weak browserManager] in
                        browserManager?.windowRegistry?.allWindows ?? []
                    },
                    window: { [weak browserManager] windowID in
                        browserManager?.windowRegistry?.windows[windowID]
                    },
                    windowContaining: { [weak browserManager] tab in
                        browserManager?.windowState(containing: tab)
                    },
                    closeTab: { [weak browserManager] tab, windowState in
                        browserManager?.closeTab(tab, in: windowState)
                    },
                    removeTab: { [weak browserManager] tabID in
                        browserManager?.tabManager.removeTab(tabID)
                    }
                )
            }
        )
    }
}
