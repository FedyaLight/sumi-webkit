//
//  BrowserWebKitCloseRoutingOwner.swift
//  Sumi
//
//  Routes normal-tab WebKit close requests to the owning browser window.
//

import Foundation
import WebKit

@MainActor
struct BrowserWebKitCloseRoutingOwner {
    struct Runtime {
        let prepareClose: (WKWebView) -> WebViewCoordinatorWebKitClosePreparation
        let cleanupTrackedWebView: (WKWebView, TrackedWebViewOwner) -> Void
        let tab: (UUID) -> Tab?
        let regularTabs: () -> [Tab]
        let allWindows: () -> [BrowserWindowState]
        let window: (UUID) -> BrowserWindowState?
        let windowContaining: (Tab) -> BrowserWindowState?
        let closeTab: (Tab, BrowserWindowState) -> Void
        let removeTab: (UUID) -> Void
    }

    @discardableResult
    func handleWebViewDidClose(_ webView: WKWebView, runtime: Runtime) -> Bool {
        switch runtime.prepareClose(webView) {
        case .deferred:
            return true
        case .ready(let trackedOwner):
            if let trackedOwner {
                return handleTrackedWebViewClose(
                    webView,
                    owner: trackedOwner,
                    runtime: runtime
                )
            }

            if let (tab, windowState) = untrackedTabContext(for: webView, runtime: runtime) {
                closeTabForWebKitCloseRequest(tab, windowState: windowState, runtime: runtime)
                return true
            }

            SumiAuxiliaryWebViewShutdown.perform(on: webView)
            return true
        }
    }

    private func handleTrackedWebViewClose(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        runtime: Runtime
    ) -> Bool {
        guard let tab = runtime.tab(owner.tabID),
              let windowState = runtime.window(owner.windowID)
        else {
            runtime.cleanupTrackedWebView(webView, owner)
            return true
        }

        runtime.closeTab(tab, windowState)
        return true
    }

    private func closeTabForWebKitCloseRequest(
        _ tab: Tab,
        windowState: BrowserWindowState?,
        runtime: Runtime
    ) {
        if let windowState {
            runtime.closeTab(tab, windowState)
            return
        }

        if let containingWindow = runtime.windowContaining(tab) {
            runtime.closeTab(tab, containingWindow)
            return
        }

        tab.performComprehensiveWebViewCleanup()
        runtime.removeTab(tab.id)
    }

    private func untrackedTabContext(
        for webView: WKWebView,
        runtime: Runtime
    ) -> (tab: Tab, windowState: BrowserWindowState?)? {
        func matches(_ tab: Tab) -> Bool {
            tab.existingWebView === webView || tab.assignedWebView === webView
        }

        for windowState in runtime.allWindows() {
            if let tab = windowState.ephemeralTabs.first(where: matches) {
                return (tab, windowState)
            }
        }

        if let tab = runtime.regularTabs().first(where: matches) {
            return (tab, runtime.windowContaining(tab))
        }

        return nil
    }
}
