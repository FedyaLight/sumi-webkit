//
//  WebViewTabScopedCleanupValidationOwner.swift
//  SumiWebRuntime
//
//  Validates deferred cleanup commands that target untracked tab WebViews.
//

import Foundation
import WebKit

@MainActor
public struct WebViewTabScopedCleanupValidationOwner {
    public struct Context {
        public let trackedOwner: (ObjectIdentifier) -> TrackedWebViewOwner?
        public let resolveWebView: (ObjectIdentifier) -> WKWebView?
        public let resolveTab: (UUID) -> (any WebRuntimeTabHandle)?
        public let allTabs: () -> [any WebRuntimeTabHandle]
        public let sessionStore: TabWebViewSessionStore?

        public init(
            trackedOwner: @escaping (ObjectIdentifier) -> TrackedWebViewOwner?,
            resolveWebView: @escaping (ObjectIdentifier) -> WKWebView?,
            resolveTab: @escaping (UUID) -> (any WebRuntimeTabHandle)?,
            allTabs: @escaping () -> [any WebRuntimeTabHandle],
            sessionStore: TabWebViewSessionStore?
        ) {
            self.trackedOwner = trackedOwner
            self.resolveWebView = resolveWebView
            self.resolveTab = resolveTab
            self.allTabs = allTabs
            self.sessionStore = sessionStore
        }
    }

    public init() {}

    public func canCleanUpTabScopedWebView(
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
        _ tab: any WebRuntimeTabHandle,
        _ webView: WKWebView,
        sessionStore: TabWebViewSessionStore?
    ) -> Bool {
        if let sessionStore {
            sessionStore.promoteLocalSessionIfNeeded(
                tabId: tab.id,
                localSession: tab.localSession
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
        let local = tab.localSession
        return local.untrackedWebView === webView
            || local.parkedWebView === webView
            || local.primaryWebView === webView
    }
}
