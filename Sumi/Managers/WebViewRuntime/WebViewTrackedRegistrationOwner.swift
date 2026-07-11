import Foundation
import WebKit
import SumiWebRuntime

/// Owns the tracked-WebView registration lifecycle: registry slots,
/// media-protection observations installed on registration, and teardown of
/// unprotected tracked WebViews.
@MainActor
final class WebViewTrackedRegistrationOwner {
    private let webViewSessions: WebViewSessionRepository
    private let mediaProtectionOwner: WebViewMediaProtectionOwner
    private let trackingLifecycleOwner: WebViewTrackingLifecycleOwner
    private let trackedCleanupExecutionOwner: WebViewTrackedCleanupExecutionOwner
    private let containsWindow: @MainActor @Sendable (UUID) -> Bool
    private let currentTabID: @MainActor @Sendable (UUID) -> UUID?
    private let selectTab: @MainActor @Sendable (UUID, UUID) -> Void
    private let refreshCompositor: @MainActor @Sendable (UUID) -> Void
    private let removeWebViewFromContainers: @MainActor (WKWebView) -> Void
    private let pruneInvalidDeferredCommands: @MainActor (String) -> Void
    private let flushDeferredProtectedCommands: @MainActor (ObjectIdentifier) -> Void
    private let finishDestructiveCleanupNavigation: @MainActor (WKWebView) -> Void
    private let performFallbackWebViewCleanup: @MainActor (WKWebView, UUID) -> Void
    private let resolvedTab: @MainActor (UUID) -> Tab?
    private let refreshPrimaryTrackedWebView: @MainActor (Tab) -> Void
    private let removeRecentVisibility: @MainActor (TrackedWebViewOwner) -> Void

    init(
        webViewSessions: WebViewSessionRepository,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        trackingLifecycleOwner: WebViewTrackingLifecycleOwner,
        trackedCleanupExecutionOwner: WebViewTrackedCleanupExecutionOwner,
        containsWindow: @escaping @MainActor @Sendable (UUID) -> Bool,
        currentTabID: @escaping @MainActor @Sendable (UUID) -> UUID?,
        selectTab: @escaping @MainActor @Sendable (UUID, UUID) -> Void,
        refreshCompositor: @escaping @MainActor @Sendable (UUID) -> Void,
        removeWebViewFromContainers: @escaping @MainActor (WKWebView) -> Void,
        pruneInvalidDeferredCommands: @escaping @MainActor (String) -> Void,
        flushDeferredProtectedCommands: @escaping @MainActor (ObjectIdentifier) -> Void,
        finishDestructiveCleanupNavigation: @escaping @MainActor (WKWebView) -> Void,
        performFallbackWebViewCleanup: @escaping @MainActor (WKWebView, UUID) -> Void,
        resolvedTab: @escaping @MainActor (UUID) -> Tab?,
        refreshPrimaryTrackedWebView: @escaping @MainActor (Tab) -> Void,
        removeRecentVisibility: @escaping @MainActor (TrackedWebViewOwner) -> Void
    ) {
        self.webViewSessions = webViewSessions
        self.mediaProtectionOwner = mediaProtectionOwner
        self.trackingLifecycleOwner = trackingLifecycleOwner
        self.trackedCleanupExecutionOwner = trackedCleanupExecutionOwner
        self.containsWindow = containsWindow
        self.currentTabID = currentTabID
        self.selectTab = selectTab
        self.refreshCompositor = refreshCompositor
        self.removeWebViewFromContainers = removeWebViewFromContainers
        self.pruneInvalidDeferredCommands = pruneInvalidDeferredCommands
        self.flushDeferredProtectedCommands = flushDeferredProtectedCommands
        self.finishDestructiveCleanupNavigation = finishDestructiveCleanupNavigation
        self.performFallbackWebViewCleanup = performFallbackWebViewCleanup
        self.resolvedTab = resolvedTab
        self.refreshPrimaryTrackedWebView = refreshPrimaryTrackedWebView
        self.removeRecentVisibility = removeRecentVisibility
    }

    @discardableResult
    func register(
        _ webView: WKWebView,
        for tabId: UUID,
        in windowId: UUID,
        didCommitPlacement: @escaping @MainActor () -> Void = {}
    ) -> WebViewTrackedRegistrationResult {
        let owner = TrackedWebViewOwner(tabID: tabId, windowID: windowId)
        let result = trackingLifecycleOwner.registerTrackedWebView(
            webView,
            for: owner,
            in: webViewSessions,
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
            },
            canDisplaceWebView: { [mediaProtectionOwner] webView in
                mediaProtectionOwner.isProtected(webView) == false
            },
            removeRecentVisibility: { [removeRecentVisibility] owner in
                removeRecentVisibility(owner)
            },
            didCommitPlacement: didCommitPlacement,
            cleanupDisplacedWebView: { [weak self] webView, tabID in
                guard let self else { return }
                if let tab = resolvedTab(tabID) {
                    tab.cleanupCloneWebView(webView)
                } else {
                    performFallbackWebViewCleanup(webView, tabID)
                }
            }
        )
        guard case .rejected = result else {
            mediaProtectionOwner.note(webView)
            if let tab = resolvedTab(tabId),
               tab.webContentRecovery.isRecoveryRequired(on: webView) {
                _ = tab.navigationRuntime.webViewRouting
                    .recoverWebContentProcess(tab.id, webView)
            }
            return result
        }
        return result
    }

    @discardableResult
    func promotePrimary(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) -> Bool {
        trackingLifecycleOwner.promoteTrackedWebViewToPrimary(
            owner: owner,
            expectedWebView: webView,
            in: webViewSessions
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
            in: webViewSessions,
            removeFromContainers: { [removeWebViewFromContainers] webView in
                removeWebViewFromContainers(webView)
            },
            uninstallRuntimeObservationsIfUntracked: { [weak self] webView in
                self?.uninstallMediaProtectionObservationsIfUntracked(webView)
            },
            pruneInvalidDeferredCommands: { [pruneInvalidDeferredCommands] reason in
                pruneInvalidDeferredCommands(reason)
            },
            forgetRecentVisibility: { [weak self] owner in
                self?.removeRecentVisibility(owner)
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
            webViewSessions: webViewSessions,
            trackingLifecycleOwner: trackingLifecycleOwner,
            runtime: cleanupExecutionRuntime()
        )
    }

    func uninstallMediaProtectionObservationsIfUntracked(_ webView: WKWebView) {
        mediaProtectionOwner.uninstallObservationsIfUntracked(
            webView,
            isTracked: webViewSessions.isIndexed(webView)
        )
    }

    func installMediaProtectionObservationsIfNeeded(on webView: WKWebView) {
        mediaProtectionOwner.installFullscreenStateObservationIfNeeded(
            on: webView,
            trackedOwner: { [webViewSessions] webView in
                webViewSessions.trackedOwner(containing: webView)
            },
            fallbackWindowID: { [webViewSessions] webView in
                webViewSessions.trackedOwner(containing: webView)?.windowID
            },
            flushDeferredProtectedCommands: { [flushDeferredProtectedCommands] webViewID in
                flushDeferredProtectedCommands(webViewID)
            },
            refreshCompositor: { [containsWindow, refreshCompositor] windowID in
                guard containsWindow(windowID) else { return }
                refreshCompositor(windowID)
            },
            selectTab: { [selectTab] tabID, windowID in
                selectTab(tabID, windowID)
            },
            isOwnerTabCurrent: { [containsWindow, currentTabID] tabID, windowID in
                containsWindow(windowID) && currentTabID(windowID) == tabID
            }
        )

        mediaProtectionOwner.installNowPlayingSessionObservationIfNeeded(
            on: webView,
            trackedOwner: { [webViewSessions] webView in
                webViewSessions.trackedOwner(containing: webView)
            },
            fallbackWindowID: { [webViewSessions] webView in
                webViewSessions.trackedOwner(containing: webView)?.windowID
            }
        )
    }

    private func cleanupExecutionRuntime() -> WebViewTrackedCleanupExecutionOwner.Runtime {
        WebViewTrackedCleanupExecutionOwner.Runtime(
            finishDestructiveCleanupSuppression: { [finishDestructiveCleanupNavigation] webView in
                finishDestructiveCleanupNavigation(webView)
            },
            uninstallRuntimeObservationsIfUntracked: { [weak self] webView in
                self?.uninstallMediaProtectionObservationsIfUntracked(webView)
            },
            pruneInvalidDeferredCommands: { [pruneInvalidDeferredCommands] reason in
                pruneInvalidDeferredCommands(reason)
            },
            fallbackCleanup: { [performFallbackWebViewCleanup] webView, tabID in
                performFallbackWebViewCleanup(webView, tabID)
            },
            forgetRecentVisibility: { [removeRecentVisibility] owner in
                removeRecentVisibility(owner)
            }
        )
    }
}
