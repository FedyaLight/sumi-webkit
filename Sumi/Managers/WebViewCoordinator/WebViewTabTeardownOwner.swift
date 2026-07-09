import Foundation
import WebKit
import SumiWebRuntime

/// Owns whole-tab WebView teardown: removing every tracked and tab-owned
/// WebView for a tab, and releasing WebViews when a tab is suspended.
/// Protected WebViews are deferred instead of mutated.
@MainActor
final class WebViewTabTeardownOwner {
    private let webViewRegistry: WindowWebViewRegistry
    private let tabWebViewSessionStore: TabWebViewSessionStore
    private let mediaProtectionOwner: WebViewMediaProtectionOwner
    private let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
    private let enqueueDeferredProtectedCommand:
        @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool
    private let cleanupUnprotectedTrackedWebView:
        @MainActor (WKWebView, TrackedWebViewOwner, Tab?) -> Void
    private let refreshPrimaryTrackedWebView: @MainActor (Tab) -> Void
    private let removeWebViewFromContainers: @MainActor (WKWebView) -> Void
    private let unregisterTrackedWebViewSlot:
        @MainActor (TrackedWebViewOwner, WKWebView) -> WKWebView?

    init(
        webViewRegistry: WindowWebViewRegistry,
        tabWebViewSessionStore: TabWebViewSessionStore,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        isWebViewProtectedFromCompositorMutation: @escaping @MainActor (WKWebView) -> Bool,
        enqueueDeferredProtectedCommand:
            @escaping @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool,
        cleanupUnprotectedTrackedWebView:
            @escaping @MainActor (WKWebView, TrackedWebViewOwner, Tab?) -> Void,
        refreshPrimaryTrackedWebView: @escaping @MainActor (Tab) -> Void,
        removeWebViewFromContainers: @escaping @MainActor (WKWebView) -> Void,
        unregisterTrackedWebViewSlot:
            @escaping @MainActor (TrackedWebViewOwner, WKWebView) -> WKWebView?
    ) {
        self.webViewRegistry = webViewRegistry
        self.tabWebViewSessionStore = tabWebViewSessionStore
        self.mediaProtectionOwner = mediaProtectionOwner
        self.isWebViewProtectedFromCompositorMutation = isWebViewProtectedFromCompositorMutation
        self.enqueueDeferredProtectedCommand = enqueueDeferredProtectedCommand
        self.cleanupUnprotectedTrackedWebView = cleanupUnprotectedTrackedWebView
        self.refreshPrimaryTrackedWebView = refreshPrimaryTrackedWebView
        self.removeWebViewFromContainers = removeWebViewFromContainers
        self.unregisterTrackedWebViewSlot = unregisterTrackedWebViewSlot
    }

    func allKnownWebViews(for tab: Tab) -> [WKWebView] {
        // Phase 6B: session/registry only (imports Tab-local notes if needed).
        tabWebViewSessionStore.allKnownWebViews(
            for: tab.id,
            localSession: tab.webViewOwnershipOwner.localSession
        )
    }

    @discardableResult
    func removeAllWebViews(
        for tab: Tab,
        closeActiveFullscreenMedia: Bool
    ) -> Bool {
        let currentEntries = webViewRegistry.windowWebViews(for: tab.id)
        let protectedCandidateWebViews = uniqueWebViews(
            tabWebViewSessionStore.protectedCandidateWebViews(
                for: tab.id,
                localSession: tab.webViewOwnershipOwner.localSession
            )
        )
        if protectedCandidateWebViews
            .contains(where: isWebViewProtectedFromCompositorMutation) {
            let protectedTrackedIDs = Set(
                currentEntries.values
                    .filter { isWebViewProtectedFromCompositorMutation($0) }
                    .map(ObjectIdentifier.init)
            )
            var closedMediaWebViewIDs: Set<ObjectIdentifier> = []

            func closeFullscreenMediaOnce(on webView: WKWebView) {
                guard closeActiveFullscreenMedia else { return }
                guard closedMediaWebViewIDs.insert(ObjectIdentifier(webView)).inserted else { return }
                mediaProtectionOwner.closeFullscreenMediaIfNeeded(on: webView)
            }

            for (windowId, protectedWebView) in currentEntries
                where isWebViewProtectedFromCompositorMutation(protectedWebView) {
                closeFullscreenMediaOnce(on: protectedWebView)
                _ = enqueueDeferredProtectedCommand(
                    .removeTrackedWebView(
                        webViewID: ObjectIdentifier(protectedWebView),
                        tabID: tab.id,
                        windowID: windowId
                    ),
                    protectedWebView,
                    "removeAllWebViews"
                )
            }
            for protectedWebView in protectedCandidateWebViews
                where isWebViewProtectedFromCompositorMutation(protectedWebView) {
                let protectedWebViewID = ObjectIdentifier(protectedWebView)
                closeFullscreenMediaOnce(on: protectedWebView)

                guard !protectedTrackedIDs.contains(protectedWebViewID) else { continue }
                _ = enqueueDeferredProtectedCommand(
                    .cleanupTabWebView(
                        webViewID: protectedWebViewID,
                        tabID: tab.id
                    ),
                    protectedWebView,
                    "removeAllWebViews.untracked"
                )
            }
            return false
        }

        let trackedEntries = currentEntries.map { windowId, webView in
            (TrackedWebViewOwner(tabID: tab.id, windowID: windowId), webView)
        }
        guard trackedEntries.isEmpty == false else { return false }

        for (owner, webView) in trackedEntries {
            cleanupUnprotectedTrackedWebView(webView, owner, tab)
        }
        refreshPrimaryTrackedWebView(tab)
        return true
    }

    @discardableResult
    func suspendWebViews(for tab: Tab, reason: String) -> Bool {
        let liveWebViews = allKnownWebViews(for: tab)
        guard !liveWebViews.isEmpty else { return false }
        guard !liveWebViews
            .contains(where: isWebViewProtectedFromCompositorMutation) else {
            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Skipping suspension cleanup for protected tab=\(tab.id.uuidString.prefix(8)) reason=\(reason)."
            }
            return false
        }

        let trackedEntries = webViewRegistry.trackedWebViews(for: tab.id)
        var cleanedIdentifiers: Set<ObjectIdentifier> = []

        func cleanup(_ webView: WKWebView) {
            let identifier = ObjectIdentifier(webView)
            guard cleanedIdentifiers.insert(identifier).inserted else { return }
            tab.cleanupCloneWebView(webView)
        }

        for (owner, webView) in trackedEntries {
            removeWebViewFromContainers(webView)
            _ = unregisterTrackedWebViewSlot(owner, webView)
            cleanup(webView)
        }

        for webView in liveWebViews {
            cleanup(webView)
        }

        tab.cancelPendingMainFrameNavigation()
        tab.clearAllWebViewOwnership()
        tabWebViewSessionStore.clearAll(for: tab.id)

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Suspension released \(cleanedIdentifiers.count) WebView(s) for tab=\(tab.id.uuidString.prefix(8)) reason=\(reason)."
        }

        return !cleanedIdentifiers.isEmpty
    }

    private func uniqueWebViews(_ webViews: [WKWebView]) -> [WKWebView] {
        var seen: Set<ObjectIdentifier> = []
        var unique: [WKWebView] = []
        for webView in webViews {
            let identifier = ObjectIdentifier(webView)
            if seen.insert(identifier).inserted {
                unique.append(webView)
            }
        }
        return unique
    }
}
