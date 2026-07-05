import Foundation
import WebKit

/// Owns the tracked-WebView registration lifecycle: registry slots,
/// media-protection observations installed on registration, and teardown of
/// unprotected tracked WebViews.
@MainActor
final class WebViewTrackedRegistrationOwner {
    struct Dependencies {
        let webViewRegistry: WindowWebViewRegistry
        let mediaProtectionOwner: WebViewMediaProtectionOwner
        let trackingLifecycleOwner: WebViewTrackingLifecycleOwner
        let trackedCleanupExecutionOwner: WebViewTrackedCleanupExecutionOwner
        let requireBrowserRuntimeContext: @MainActor () -> WebViewCoordinatorBrowserRuntimeContext
        let removeWebViewFromContainers: @MainActor (WKWebView) -> Void
        let pruneInvalidDeferredCommands: @MainActor (String) -> Void
        let flushDeferredProtectedCommands: @MainActor (ObjectIdentifier) -> Void
        let finishDestructiveCleanupNavigation: @MainActor (WKWebView) -> Void
        let performFallbackWebViewCleanup: @MainActor (WKWebView, UUID) -> Void
        let resolvedTab: @MainActor (UUID) -> Tab?
        let refreshPrimaryTrackedWebView: @MainActor (Tab) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func register(
        _ webView: WKWebView,
        for tabId: UUID,
        in windowId: UUID
    ) {
        let owner = TrackedWebViewOwner(tabID: tabId, windowID: windowId)
        dependencies.mediaProtectionOwner.note(webView)
        dependencies.trackingLifecycleOwner.registerTrackedWebView(
            webView,
            for: owner,
            in: dependencies.webViewRegistry,
            removeFromContainers: { [dependencies] webView in
                dependencies.removeWebViewFromContainers(webView)
            },
            installRuntimeObservations: { [weak self] webView in
                self?.installMediaProtectionObservationsIfNeeded(on: webView)
            },
            uninstallRuntimeObservationsIfUntracked: { [weak self] webView in
                self?.uninstallMediaProtectionObservationsIfUntracked(webView)
            },
            pruneInvalidDeferredCommands: { [dependencies] reason in
                dependencies.pruneInvalidDeferredCommands(reason)
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
        dependencies.trackingLifecycleOwner.unregisterTrackedWebViewSlot(
            owner: owner,
            expectedWebView: expectedWebView,
            removeFromSuperview: removeFromSuperview,
            removeRecentVisibility: removeRecentVisibility,
            in: dependencies.webViewRegistry,
            removeFromContainers: { [dependencies] webView in
                dependencies.removeWebViewFromContainers(webView)
            },
            uninstallRuntimeObservationsIfUntracked: { [weak self] webView in
                self?.uninstallMediaProtectionObservationsIfUntracked(webView)
            },
            pruneInvalidDeferredCommands: { [dependencies] reason in
                dependencies.pruneInvalidDeferredCommands(reason)
            }
        )
    }

    func cleanupTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) {
        let tab = dependencies.resolvedTab(owner.tabID)
        cleanupUnprotectedTrackedWebView(
            webView,
            owner: owner,
            tab: tab
        )
        if let tab {
            dependencies.refreshPrimaryTrackedWebView(tab)
        }
    }

    func cleanupUnprotectedTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        tab: Tab?
    ) {
        dependencies.trackedCleanupExecutionOwner.cleanupUnprotectedTrackedWebView(
            webView,
            owner: owner,
            tab: tab,
            webViewRegistry: dependencies.webViewRegistry,
            trackingLifecycleOwner: dependencies.trackingLifecycleOwner,
            runtime: cleanupExecutionRuntime()
        )
    }

    func uninstallMediaProtectionObservationsIfUntracked(_ webView: WKWebView) {
        dependencies.mediaProtectionOwner.uninstallObservationsIfUntracked(
            webView,
            isTracked: dependencies.webViewRegistry.isIndexed(webView)
        )
    }

    private func installMediaProtectionObservationsIfNeeded(on webView: WKWebView) {
        dependencies.mediaProtectionOwner.installFullscreenStateObservationIfNeeded(
            on: webView,
            trackedOwner: { [dependencies] webView in
                dependencies.webViewRegistry.trackedOwner(containing: webView)
            },
            fallbackWindowID: { [dependencies] webView in
                dependencies.webViewRegistry.trackedOwner(containing: webView)?.windowID
            },
            flushDeferredProtectedCommands: { [dependencies] webViewID in
                dependencies.flushDeferredProtectedCommands(webViewID)
            },
            refreshCompositor: { [dependencies] windowID in
                let runtimeContext = dependencies.requireBrowserRuntimeContext()
                guard let windowState = runtimeContext.window(windowID)
                else {
                    return
                }
                runtimeContext.refreshCompositor(windowState)
            },
            selectTab: { [dependencies] tabID, windowID in
                dependencies.requireBrowserRuntimeContext().selectTab(tabID, windowID)
            },
            isOwnerTabCurrent: { [dependencies] tabID, windowID in
                let runtimeContext = dependencies.requireBrowserRuntimeContext()
                guard let windowState = runtimeContext.window(windowID) else {
                    return false
                }
                return runtimeContext.currentTab(windowState)?.id == tabID
            }
        )

        dependencies.mediaProtectionOwner.installNowPlayingSessionObservationIfNeeded(
            on: webView,
            trackedOwner: { [dependencies] webView in
                dependencies.webViewRegistry.trackedOwner(containing: webView)
            },
            fallbackWindowID: { [dependencies] webView in
                dependencies.webViewRegistry.trackedOwner(containing: webView)?.windowID
            }
        )
    }

    private func cleanupExecutionRuntime() -> WebViewTrackedCleanupExecutionOwner.Runtime {
        WebViewTrackedCleanupExecutionOwner.Runtime(
            finishDestructiveCleanupSuppression: { [dependencies] webView in
                dependencies.finishDestructiveCleanupNavigation(webView)
            },
            removeFromContainers: { [dependencies] webView in
                dependencies.removeWebViewFromContainers(webView)
            },
            uninstallRuntimeObservationsIfUntracked: { [weak self] webView in
                self?.uninstallMediaProtectionObservationsIfUntracked(webView)
            },
            pruneInvalidDeferredCommands: { [dependencies] reason in
                dependencies.pruneInvalidDeferredCommands(reason)
            },
            fallbackCleanup: { [dependencies] webView, tabID in
                dependencies.performFallbackWebViewCleanup(webView, tabID)
            }
        )
    }
}

extension WebViewTrackedRegistrationOwner.Dependencies {
    @MainActor
    static func live(coordinator: WebViewCoordinator) -> Self {
        Self(
            webViewRegistry: coordinator.webViewRegistry,
            mediaProtectionOwner: coordinator.mediaProtectionOwner,
            trackingLifecycleOwner: coordinator.webViewTrackingLifecycleOwner,
            trackedCleanupExecutionOwner: coordinator.trackedCleanupExecutionOwner,
            requireBrowserRuntimeContext: { [weak coordinator] in
                guard let coordinator else {
                    preconditionFailure("WebViewCoordinator dependency used after deallocation")
                }
                return coordinator.runtimeContextStore.requireBrowser()
            },
            removeWebViewFromContainers: { [weak coordinator] webView in
                coordinator?.removeWebViewFromContainers(webView)
            },
            pruneInvalidDeferredCommands: { [weak coordinator] reason in
                coordinator?.pruneInvalidDeferredProtectedCommands(reason: reason)
            },
            flushDeferredProtectedCommands: { [weak coordinator] webViewID in
                coordinator?.flushDeferredProtectedCommands(for: webViewID)
            },
            finishDestructiveCleanupNavigation: { [weak coordinator] webView in
                coordinator?.finishDestructiveDataCleanupNavigation(on: webView)
            },
            performFallbackWebViewCleanup: { [weak coordinator] webView, tabID in
                coordinator?.performFallbackWebViewCleanup(webView, tabId: tabID)
            },
            resolvedTab: { [weak coordinator] tabID in
                coordinator?.resolvedTab(with: tabID)
            },
            refreshPrimaryTrackedWebView: { [weak coordinator] tab in
                coordinator?.refreshPrimaryTrackedWebView(for: tab)
            }
        )
    }
}
