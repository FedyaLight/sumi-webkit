import WebKit

@MainActor
extension BrowserManager {
    @discardableResult
    func handleWebViewDidClose(_ webView: WKWebView) -> Bool {
        if glanceManager.handleWebViewDidClose(webView) {
            return true
        }

        if auxiliaryWindowManager.contains(webView: webView) {
            auxiliaryWindowManager.teardown(for: webView, reason: .webViewDidClose)
            return true
        }

        return handleNormalWebViewDidClose(webView)
    }

    @discardableResult
    func handleNormalWebViewDidClose(_ webView: WKWebView) -> Bool {
        BrowserWebKitCloseRoutingOwner().handleWebViewDidClose(
            webView,
            runtime: webKitCloseRoutingRuntime()
        )
    }

    private func webKitCloseRoutingRuntime() -> BrowserWebKitCloseRoutingOwner.Runtime {
        BrowserWebKitCloseRoutingOwner.Runtime(
            prepareClose: { [weak self] webView in
                self?.requireWebViewCoordinator().prepareWebKitClose(webView)
                    ?? .ready(trackedOwner: nil)
            },
            cleanupTrackedWebView: { [weak self] webView, owner in
                self?.requireWebViewCoordinator().cleanupTrackedWebViewAfterWebKitClose(
                    webView,
                    owner: owner
                )
            },
            tab: { [weak self] tabID in
                self?.tabManager.tab(for: tabID)
            },
            regularTabs: { [weak self] in
                self?.tabManager.allTabs() ?? []
            },
            allWindows: { [weak self] in
                self?.windowRegistry?.allWindows ?? []
            },
            window: { [weak self] windowID in
                self?.windowRegistry?.windows[windowID]
            },
            windowContaining: { [weak self] tab in
                self?.windowState(containing: tab)
            },
            closeTab: { [weak self] tab, windowState in
                self?.closeTab(tab, in: windowState)
            },
            removeTab: { [weak self] tabID in
                self?.tabManager.removeTab(tabID)
            }
        )
    }

    func closeAuxiliaryMiniWindow(
        for tab: Tab,
        reason: AuxiliaryWindowCloseReason = .extensionRequestedClose
    ) {
        guard tabManager.isAuxiliaryMiniWindowTab(tab) else { return }

        if let webView = auxiliaryWindowManager.session(for: tab)?.webView {
            auxiliaryWindowManager.teardown(for: webView, reason: reason)
            return
        }

        tabManager.removeAuxiliaryMiniWindowTab(tab)
        BrowserManagerRuntimeWiring.notifyExtensionTabClosed(tab, for: self)
    }
}
