import Foundation
import WebKit

/// Owns whole-tab WebView teardown: removing every tracked and tab-owned
/// WebView for a tab, and releasing WebViews when a tab is suspended.
/// Protected WebViews are deferred instead of mutated.
@MainActor
final class WebViewTabTeardownOwner {
    struct Dependencies {
        let webViewRegistry: WindowWebViewRegistry
        let tabWebViewSessionStore: TabWebViewSessionStore
        let mediaProtectionOwner: WebViewMediaProtectionOwner
        let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
        let enqueueDeferredProtectedCommand:
            @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool
        let cleanupUnprotectedTrackedWebView:
            @MainActor (WKWebView, TrackedWebViewOwner, Tab?) -> Void
        let refreshPrimaryTrackedWebView: @MainActor (Tab) -> Void
        let removeWebViewFromContainers: @MainActor (WKWebView) -> Void
        let unregisterTrackedWebViewSlot:
            @MainActor (TrackedWebViewOwner, WKWebView) -> WKWebView?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func allKnownWebViews(for tab: Tab) -> [WKWebView] {
        // Phase 6B: session/registry only (imports Tab mirror once if session is empty).
        dependencies.tabWebViewSessionStore.allKnownWebViews(for: tab)
    }

    @discardableResult
    func removeAllWebViews(
        for tab: Tab,
        closeActiveFullscreenMedia: Bool
    ) -> Bool {
        let currentEntries = dependencies.webViewRegistry.windowWebViews(for: tab.id)
        let protectedCandidateWebViews = uniqueWebViews(
            dependencies.tabWebViewSessionStore.protectedCandidateWebViews(for: tab)
        )
        if protectedCandidateWebViews
            .contains(where: dependencies.isWebViewProtectedFromCompositorMutation) {
            let protectedTrackedIDs = Set(
                currentEntries.values
                    .filter { dependencies.isWebViewProtectedFromCompositorMutation($0) }
                    .map(ObjectIdentifier.init)
            )
            var closedMediaWebViewIDs: Set<ObjectIdentifier> = []

            func closeFullscreenMediaOnce(on webView: WKWebView) {
                guard closeActiveFullscreenMedia else { return }
                guard closedMediaWebViewIDs.insert(ObjectIdentifier(webView)).inserted else { return }
                dependencies.mediaProtectionOwner.closeFullscreenMediaIfNeeded(on: webView)
            }

            for (windowId, protectedWebView) in currentEntries
                where dependencies.isWebViewProtectedFromCompositorMutation(protectedWebView) {
                closeFullscreenMediaOnce(on: protectedWebView)
                _ = dependencies.enqueueDeferredProtectedCommand(
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
                where dependencies.isWebViewProtectedFromCompositorMutation(protectedWebView) {
                let protectedWebViewID = ObjectIdentifier(protectedWebView)
                closeFullscreenMediaOnce(on: protectedWebView)

                guard !protectedTrackedIDs.contains(protectedWebViewID) else { continue }
                _ = dependencies.enqueueDeferredProtectedCommand(
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
            dependencies.cleanupUnprotectedTrackedWebView(webView, owner, tab)
        }
        dependencies.refreshPrimaryTrackedWebView(tab)
        return true
    }

    @discardableResult
    func suspendWebViews(for tab: Tab, reason: String) -> Bool {
        let liveWebViews = allKnownWebViews(for: tab)
        guard !liveWebViews.isEmpty else { return false }
        guard !liveWebViews
            .contains(where: dependencies.isWebViewProtectedFromCompositorMutation) else {
            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Skipping suspension cleanup for protected tab=\(tab.id.uuidString.prefix(8)) reason=\(reason)."
            }
            return false
        }

        let trackedEntries = dependencies.webViewRegistry.trackedWebViews(for: tab.id)
        var cleanedIdentifiers: Set<ObjectIdentifier> = []

        func cleanup(_ webView: WKWebView) {
            let identifier = ObjectIdentifier(webView)
            guard cleanedIdentifiers.insert(identifier).inserted else { return }
            tab.cleanupCloneWebView(webView)
        }

        for (owner, webView) in trackedEntries {
            dependencies.removeWebViewFromContainers(webView)
            _ = dependencies.unregisterTrackedWebViewSlot(owner, webView)
            cleanup(webView)
        }

        for webView in liveWebViews {
            cleanup(webView)
        }

        tab.cancelPendingMainFrameNavigation()
        tab.clearAllWebViewOwnership()
        dependencies.tabWebViewSessionStore.clearAll(for: tab.id)

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

extension WebViewTabTeardownOwner.Dependencies {
    @MainActor
    static func live(coordinator: WebViewCoordinator) -> Self {
        Self(
            webViewRegistry: coordinator.webViewRegistry,
            tabWebViewSessionStore: coordinator.tabWebViewSessionStore,
            mediaProtectionOwner: coordinator.mediaProtectionOwner,
            isWebViewProtectedFromCompositorMutation: { [weak coordinator] webView in
                coordinator?.isWebViewProtectedFromCompositorMutation(webView) ?? false
            },
            enqueueDeferredProtectedCommand: { [weak coordinator] command, webView, reason in
                coordinator?.enqueueDeferredProtectedCommand(
                    command,
                    for: webView,
                    reason: reason
                ) ?? false
            },
            cleanupUnprotectedTrackedWebView: { [weak coordinator] webView, owner, tab in
                coordinator?.cleanupUnprotectedTrackedWebView(
                    webView,
                    owner: owner,
                    tab: tab
                )
            },
            refreshPrimaryTrackedWebView: { [weak coordinator] tab in
                coordinator?.refreshPrimaryTrackedWebView(for: tab)
            },
            removeWebViewFromContainers: { [weak coordinator] webView in
                coordinator?.removeWebViewFromContainers(webView)
            },
            unregisterTrackedWebViewSlot: { [weak coordinator] owner, expectedWebView in
                coordinator?.unregisterTrackedWebViewSlot(
                    owner: owner,
                    expectedWebView: expectedWebView
                )
            }
        )
    }
}
