import Foundation
import WebKit
import SumiWebRuntime

/// Owns the tracked-WebView registration lifecycle: registry slots,
/// media-protection observations installed on registration, and teardown of
/// unprotected tracked WebViews.
@MainActor
final class WebViewTrackedRegistrationOwner {
    private let webViewRegistry: WindowWebViewRegistry
    private let mediaProtectionOwner: WebViewMediaProtectionOwner
    private let trackingLifecycleOwner: WebViewTrackingLifecycleOwner
    private let trackedCleanupExecutionOwner: WebViewTrackedCleanupExecutionOwner
    private let requireBrowserRuntimeContext: @MainActor () -> WebViewCoordinatorBrowserRuntimeContext
    private let removeWebViewFromContainers: @MainActor (WKWebView) -> Void
    private let pruneInvalidDeferredCommands: @MainActor (String) -> Void
    private let flushDeferredProtectedCommands: @MainActor (ObjectIdentifier) -> Void
    private let finishDestructiveCleanupNavigation: @MainActor (WKWebView) -> Void
    private let performFallbackWebViewCleanup: @MainActor (WKWebView, UUID) -> Void
    private let resolvedTab: @MainActor (UUID) -> Tab?
    private let refreshPrimaryTrackedWebView: @MainActor (Tab) -> Void

    init(
        webViewRegistry: WindowWebViewRegistry,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        trackingLifecycleOwner: WebViewTrackingLifecycleOwner,
        trackedCleanupExecutionOwner: WebViewTrackedCleanupExecutionOwner,
        requireBrowserRuntimeContext: @escaping @MainActor () -> WebViewCoordinatorBrowserRuntimeContext,
        removeWebViewFromContainers: @escaping @MainActor (WKWebView) -> Void,
        pruneInvalidDeferredCommands: @escaping @MainActor (String) -> Void,
        flushDeferredProtectedCommands: @escaping @MainActor (ObjectIdentifier) -> Void,
        finishDestructiveCleanupNavigation: @escaping @MainActor (WKWebView) -> Void,
        performFallbackWebViewCleanup: @escaping @MainActor (WKWebView, UUID) -> Void,
        resolvedTab: @escaping @MainActor (UUID) -> Tab?,
        refreshPrimaryTrackedWebView: @escaping @MainActor (Tab) -> Void
    ) {
        self.webViewRegistry = webViewRegistry
        self.mediaProtectionOwner = mediaProtectionOwner
        self.trackingLifecycleOwner = trackingLifecycleOwner
        self.trackedCleanupExecutionOwner = trackedCleanupExecutionOwner
        self.requireBrowserRuntimeContext = requireBrowserRuntimeContext
        self.removeWebViewFromContainers = removeWebViewFromContainers
        self.pruneInvalidDeferredCommands = pruneInvalidDeferredCommands
        self.flushDeferredProtectedCommands = flushDeferredProtectedCommands
        self.finishDestructiveCleanupNavigation = finishDestructiveCleanupNavigation
        self.performFallbackWebViewCleanup = performFallbackWebViewCleanup
        self.resolvedTab = resolvedTab
        self.refreshPrimaryTrackedWebView = refreshPrimaryTrackedWebView
    }

    func register(
        _ webView: WKWebView,
        for tabId: UUID,
        in windowId: UUID
    ) {
        let owner = TrackedWebViewOwner(tabID: tabId, windowID: windowId)
        mediaProtectionOwner.note(webView)
        trackingLifecycleOwner.registerTrackedWebView(
            webView,
            for: owner,
            in: webViewRegistry,
            removeFromContainers: { [removeWebViewFromContainers] webView in
                removeWebViewFromContainers(webView)
            },
            installRuntimeObservations: { [weak self] webView in
                self?.installMediaProtectionObservationsIfNeeded(on: webView)
            },
            uninstallRuntimeObservationsIfUntracked: { [weak self] webView in
                self?.uninstallMediaProtectionObservationsIfUntracked(webView)
            },
            pruneInvalidDeferredCommands: { [pruneInvalidDeferredCommands] reason in
                pruneInvalidDeferredCommands(reason)
            }
        )
    }

    @discardableResult
    func unregisterSlot(
        owner: TrackedWebViewOwner,
        expectedWebView: WKWebView? = nil,
        removeFromSuperview: Bool = false,
        removeRecentVisibility: Bool = true
    ) -> WKWebView? {
        trackingLifecycleOwner.unregisterTrackedWebViewSlot(
            owner: owner,
            expectedWebView: expectedWebView,
            removeFromSuperview: removeFromSuperview,
            removeRecentVisibility: removeRecentVisibility,
            in: webViewRegistry,
            removeFromContainers: { [removeWebViewFromContainers] webView in
                removeWebViewFromContainers(webView)
            },
            uninstallRuntimeObservationsIfUntracked: { [weak self] webView in
                self?.uninstallMediaProtectionObservationsIfUntracked(webView)
            },
            pruneInvalidDeferredCommands: { [pruneInvalidDeferredCommands] reason in
                pruneInvalidDeferredCommands(reason)
            }
        )
    }

    func cleanupTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) {
        let tab = resolvedTab(owner.tabID)
        cleanupUnprotectedTrackedWebView(
            webView,
            owner: owner,
            tab: tab
        )
        if let tab {
            refreshPrimaryTrackedWebView(tab)
        }
    }

    func cleanupUnprotectedTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        tab: Tab?
    ) {
        trackedCleanupExecutionOwner.cleanupUnprotectedTrackedWebView(
            webView,
            owner: owner,
            tab: tab,
            webViewRegistry: webViewRegistry,
            trackingLifecycleOwner: trackingLifecycleOwner,
            runtime: cleanupExecutionRuntime()
        )
    }

    func uninstallMediaProtectionObservationsIfUntracked(_ webView: WKWebView) {
        mediaProtectionOwner.uninstallObservationsIfUntracked(
            webView,
            isTracked: webViewRegistry.isIndexed(webView)
        )
    }

    private func installMediaProtectionObservationsIfNeeded(on webView: WKWebView) {
        mediaProtectionOwner.installFullscreenStateObservationIfNeeded(
            on: webView,
            trackedOwner: { [webViewRegistry] webView in
                webViewRegistry.trackedOwner(containing: webView)
            },
            fallbackWindowID: { [webViewRegistry] webView in
                webViewRegistry.trackedOwner(containing: webView)?.windowID
            },
            flushDeferredProtectedCommands: { [flushDeferredProtectedCommands] webViewID in
                flushDeferredProtectedCommands(webViewID)
            },
            refreshCompositor: { [requireBrowserRuntimeContext] windowID in
                let runtimeContext = requireBrowserRuntimeContext()
                guard runtimeContext.window(windowID) != nil else {
                    return
                }
                runtimeContext.refreshCompositor(windowID)
            },
            selectTab: { [requireBrowserRuntimeContext] tabID, windowID in
                requireBrowserRuntimeContext().selectTab(tabID, windowID)
            },
            isOwnerTabCurrent: { [requireBrowserRuntimeContext] tabID, windowID in
                let runtimeContext = requireBrowserRuntimeContext()
                guard let windowHandle = runtimeContext.window(windowID) else {
                    return false
                }
                return runtimeContext.currentTab(windowHandle)?.id == tabID
            }
        )

        mediaProtectionOwner.installNowPlayingSessionObservationIfNeeded(
            on: webView,
            trackedOwner: { [webViewRegistry] webView in
                webViewRegistry.trackedOwner(containing: webView)
            },
            fallbackWindowID: { [webViewRegistry] webView in
                webViewRegistry.trackedOwner(containing: webView)?.windowID
            }
        )
    }

    private func cleanupExecutionRuntime() -> WebViewTrackedCleanupExecutionOwner.Runtime {
        WebViewTrackedCleanupExecutionOwner.Runtime(
            finishDestructiveCleanupSuppression: { [finishDestructiveCleanupNavigation] webView in
                finishDestructiveCleanupNavigation(webView)
            },
            removeFromContainers: { [removeWebViewFromContainers] webView in
                removeWebViewFromContainers(webView)
            },
            uninstallRuntimeObservationsIfUntracked: { [weak self] webView in
                self?.uninstallMediaProtectionObservationsIfUntracked(webView)
            },
            pruneInvalidDeferredCommands: { [pruneInvalidDeferredCommands] reason in
                pruneInvalidDeferredCommands(reason)
            },
            fallbackCleanup: { [performFallbackWebViewCleanup] webView, tabID in
                performFallbackWebViewCleanup(webView, tabID)
            }
        )
    }
}
