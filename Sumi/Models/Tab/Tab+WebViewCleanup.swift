import Foundation
import WebKit

extension Tab {
    func unloadWebView() {
        TabWebViewCleanupOwner.unloadWebView(context: webViewCleanupContext())
    }

    /// MEMORY LEAK FIX: Comprehensive WebView cleanup to prevent memory leaks
    public func cleanupCloneWebView(_ webView: WKWebView) {
        TabWebViewCleanupOwner.cleanupWebView(webView, context: webViewCleanupContext())
    }

    public func webViewsWillLeaveRuntime(_ webViews: [WKWebView]) {
        let departing = webViewRetirementLedger.claimLogicalDeparture(webViews)
        guard departing.isEmpty == false else { return }
        cancelConfigurationPolicy(for: departing)
        TabWebViewCleanupOwner.preparePermissionLifecycleForRetirement(
            departing,
            context: webViewCleanupContext()
        )
        let departingIDs = Set(departing.map(ObjectIdentifier.init))
        let preferredAuthority = resolvedCurrentWebView().flatMap {
            departingIDs.contains(ObjectIdentifier($0)) ? nil : $0
        }
        webViewsDidLeaveNavigationRuntime(
            departing,
            preferredAuthorityWebView: preferredAuthority
        )
    }

    public func destroyRetiredWebView(_ webView: WKWebView) {
        guard webViewRetirementLedger.claimPhysicalDestruction(webView) else {
            return
        }
        TabWebViewCleanupOwner.destroyRetiredWebView(
            webView,
            context: webViewCleanupContext()
        )
    }

    /// MEMORY LEAK FIX: Comprehensive cleanup for the main tab WebView
    @discardableResult
    public func performComprehensiveWebViewCleanup() -> Bool {
        TabWebViewCleanupOwner.performComprehensiveCleanup(
            context: webViewCleanupContext()
        )
    }

    private func webViewCleanupContext() -> TabWebViewCleanupOwner.Context {
        let cleanupRuntime = navigationRuntime.webViewCleanupRuntime
        return TabWebViewCleanupOwner.Context(
            tabId: id,
            tabName: { self.name },
            handlePermissionLifecycleEvent: { [weak self] event in
                self?.navigationRuntime.permissionRuntime.handlePermissionLifecycleEvent(event)
            },
            deferProtectedWebViewCleanup: cleanupRuntime.deferProtectedWebViewCleanup,
            shutdownRuntime: SumiWebViewShutdown.NormalTabRuntime(
                removeWebViewFromContainers: cleanupRuntime.removeWebViewFromContainers
            ),
            notifyNowPlayingTabUnloaded: { tabId in
                self.mediaRuntime.callbacks.notifyNowPlayingTabUnloaded(tabId)
            },
            remainingOwnedWebViews: { self.webViewSession.allKnownWebViews },
            clearDetachedWebViews: { self.clearAllWebViewOwnership() },
            removeAllWebViews: { intent in
                cleanupRuntime.removeAllWebViews(
                    self,
                    intent
                )
            },
            currentPermissionPageId: { self.currentPermissionPageId() },
            profilePartitionId: { self.resolveProfile()?.id.uuidString },
            invalidatePermissionPageForReplacement: { reason in
                self.invalidatePermissionPageForReplacement(reason: reason)
            },
            claimLogicalDeparture: { webViews in
                self.webViewRetirementLedger.claimLogicalDeparture(webViews)
            },
            claimPhysicalDestruction: { webView in
                self.webViewRetirementLedger.claimPhysicalDestruction(webView)
            },
            webViewDidLeaveRuntime: { webView in
                self.webViewDidLeaveNavigationRuntime(webView)
            },
            resetPlaybackActivity: {
                self.resetPlaybackActivity()
            },
            setLoadingIdle: {
                self.loadingState = .idle
            }
        )
    }
}
