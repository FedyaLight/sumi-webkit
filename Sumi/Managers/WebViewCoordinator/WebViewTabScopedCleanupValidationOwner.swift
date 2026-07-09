//
//  WebViewTabScopedCleanupValidationOwner.swift
//  Sumi
//
//  Validates deferred cleanup commands that target untracked tab WebViews.
//

import Foundation
import WebKit
import SumiWebRuntime

@MainActor
struct WebViewTabScopedCleanupValidationOwner {
    struct Context {
        let trackedOwner: (ObjectIdentifier) -> TrackedWebViewOwner?
        let resolveWebView: (ObjectIdentifier) -> WKWebView?
        let resolveTab: (UUID) -> Tab?
        let allTabs: () -> [Tab]
        let sessionStore: TabWebViewSessionStore?
    }

    func canCleanUpTabScopedWebView(
        with webViewID: ObjectIdentifier,
        tabID: UUID,
        context: Context
    ) -> Bool {
        guard context.trackedOwner(webViewID) == nil else {
            return false
        }

        guard let webView = context.resolveWebView(webViewID) else {
            return false
        }

        if let tab = context.resolveTab(tabID),
           tabOwnsUntrackedWebView(tab, webView, sessionStore: context.sessionStore) {
            return true
        }

        guard let owningTab = context.allTabs().first(where: { tab in
            tabOwnsUntrackedWebView(tab, webView, sessionStore: context.sessionStore)
        }) else {
            return true
        }

        return owningTab.id == tabID
    }

    private func tabOwnsUntrackedWebView(
        _ tab: Tab,
        _ webView: WKWebView,
        sessionStore: TabWebViewSessionStore?
    ) -> Bool {
        if let sessionStore {
            sessionStore.promoteLocalSessionIfNeeded(
                tabId: tab.id,
                localSession: tab.webViewOwnershipOwner.localSession
            )
            let session = sessionStore.session(for: tab.id)
            if session.untrackedWebView === webView
                || session.parkedWebView === webView
                || session.primaryWebView === webView {
                return true
            }
            return false
        }
        // Pre-runtime / tests without a store: Tab-local session notes.
        let local = tab.webViewOwnershipOwner.localSession
        return local.untrackedWebView === webView
            || local.parkedWebView === webView
            || local.primaryWebView === webView
    }
}
