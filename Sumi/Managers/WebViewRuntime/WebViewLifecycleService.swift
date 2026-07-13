import Foundation
import SumiWebRuntime
import WebKit

/// Owns the complete WebView teardown protocol.
///
/// Callers enter here before a WebView is removed from a tab, window, or the
/// browser runtime. The service preserves the ordering between recovery
/// cancellation, ownership release, protected-command deferral, compositor
/// detachment, and final WebKit shutdown.
@MainActor
final class WebViewLifecycleService {
    private let webViewSessions: WebViewSessionRepository
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let ownershipQuery: WebViewOwnershipQuery
    private let resolveTab: @MainActor (UUID) -> Tab?
    private let processRecovery: WebContentProcessRecoveryService
    private let deferredProtectedCommands: DeferredProtectedCommandScheduler
    private let mediaProtection: WebViewMediaProtectionOwner
    private let websiteDataCleanup: WebsiteDataCleanupService
    private let replacementPipeline: WebViewReplacementPipeline
    private let protection: WebViewProtectionRuntime
    private let compositor: WebViewCompositorRuntime
    private let visibility: WebViewVisibilityRuntime
    private let visibleRuntime: VisibleWebViewRuntimeOwner
    private let cleanupScope: WebViewCleanupScopeOwner
    private let trackedRegistration: WebViewTrackedRegistrationOwner
    private let physicalCleanup: WebViewPhysicalCleanupService
    private let runtimeAssembler: WebViewRuntimeAssembler

    init(
        webViewSessions: WebViewSessionRepository,
        runtimeTabs: WebViewRuntimeTabRegistry,
        ownershipQuery: WebViewOwnershipQuery,
        resolveTab: @escaping @MainActor (UUID) -> Tab?,
        processRecovery: WebContentProcessRecoveryService,
        deferredProtectedCommands: DeferredProtectedCommandScheduler,
        mediaProtection: WebViewMediaProtectionOwner,
        websiteDataCleanup: WebsiteDataCleanupService,
        replacementPipeline: WebViewReplacementPipeline,
        protection: WebViewProtectionRuntime,
        compositor: WebViewCompositorRuntime,
        visibility: WebViewVisibilityRuntime,
        visibleRuntime: VisibleWebViewRuntimeOwner,
        cleanupScope: WebViewCleanupScopeOwner,
        trackedRegistration: WebViewTrackedRegistrationOwner,
        physicalCleanup: WebViewPhysicalCleanupService,
        runtimeAssembler: WebViewRuntimeAssembler
    ) {
        self.webViewSessions = webViewSessions
        self.runtimeTabs = runtimeTabs
        self.ownershipQuery = ownershipQuery
        self.resolveTab = resolveTab
        self.processRecovery = processRecovery
        self.deferredProtectedCommands = deferredProtectedCommands
        self.mediaProtection = mediaProtection
        self.websiteDataCleanup = websiteDataCleanup
        self.replacementPipeline = replacementPipeline
        self.protection = protection
        self.compositor = compositor
        self.visibility = visibility
        self.visibleRuntime = visibleRuntime
        self.cleanupScope = cleanupScope
        self.trackedRegistration = trackedRegistration
        self.physicalCleanup = physicalCleanup
        self.runtimeAssembler = runtimeAssembler
    }

    private lazy var tabTeardown = WebViewTabTeardownOwner(
        webViewSessions: webViewSessions,
        mediaProtectionOwner: mediaProtection,
        isWebViewProtectedFromCompositorMutation: { [weak self] webView in
            self?.protection.isProtected(webView) ?? false
        },
        enqueueDeferredProtectedCommand: { [weak self] command, webView, reason in
            self?.protection.schedule(
                command,
                for: webView,
                reason: reason
            ).wasScheduled ?? false
        },
        cleanupUnprotectedTrackedWebView: { [weak self] webView, owner, tabHandle in
            guard let self else { return }
            self.cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: self.tabForPackageCallback(tabHandle)
            )
        },
        cleanupUnprotectedDetachedWebView: { [weak self] webView, tabID, tabHandle in
            guard let self else { return }
            if let tab = self.tabForPackageCallback(tabHandle) {
                tab.cleanupCloneWebView(webView)
            } else {
                self.physicalCleanup.clean(webView, tabID: tabID)
            }
        },
        refreshPrimaryTrackedWebView: { [weak self] tabHandle in
            guard let self,
                  let tab = self.tabForPackageCallback(tabHandle) else {
                return
            }
            self.visibility.refreshPrimaryWebView(for: tab)
        },
        removeWebViewFromContainers: { [weak self] webView in
            self?.compositor.removeWebViewFromContainers(webView)
        },
        unregisterTrackedWebViewSlot: { [weak self] owner, expectedWebView in
            self?.trackedRegistration.unregisterSlot(
                owner: owner,
                expectedWebView: expectedWebView
            )
        }
    )

    private lazy var windowCleanup = WebViewWindowCleanupOwner(
        cleanupScopeOwner: cleanupScope,
        webViewSessions: webViewSessions,
        visibleWebViewRuntimeOwner: visibleRuntime,
        mediaProtectionOwner: mediaProtection,
        tabForID: { [resolveTab] tabID in
            resolveTab(tabID)
        },
        isWebViewProtectedFromCompositorMutation: { [weak self] webView in
            self?.protection.isProtected(webView) ?? false
        },
        enqueueDeferredProtectedCommand: { [weak self] command, webView, reason in
            self?.protection.schedule(
                command,
                for: webView,
                reason: reason
            ).wasScheduled ?? false
        },
        cleanupUnprotectedTrackedWebView: { [weak self] webView, owner, tabHandle in
            guard let self else { return }
            self.cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: self.tabForPackageCallback(tabHandle)
            )
        },
        refreshPrimaryTrackedWebView: { [weak self] tabHandle in
            guard let self,
                  let tab = self.tabForPackageCallback(tabHandle) else {
                return
            }
            self.visibility.refreshPrimaryWebView(for: tab)
        },
        removeCompositorContainerView: { [weak self] windowID in
            self?.compositor.removeContainer(for: windowID)
        },
        flushDeferredProtectedCommands: { [weak self] webViewID in
            self?.protection.flush(for: webViewID)
        },
        finishCleanupSuppression: { [weak self] webViewIDs in
            self?.protection.finishCleanupSuppression(for: webViewIDs)
        }
    )

    func cleanupWindow(_ windowID: UUID) {
        windowCleanup.cleanupWindow(windowID)
    }

    func cleanupAllWebViews() {
        windowCleanup.cleanupAllWebViews()
    }

    @discardableResult
    func removeAllWebViews(
        for tab: Tab,
        closeActiveFullscreenMedia: Bool = false,
        intent: TabWebViewTeardownIntent
    ) -> WebViewTabTeardownResult {
        switch intent {
        case .suspension:
            guard runtimeTabs.bind(tab).isAccepted else { return .none }
        case .retirement:
            guard runtimeTabs.beginRetirement(tab) else { return .none }
        }
        let result = tabTeardown.removeAllWebViews(
            for: tab,
            closeActiveFullscreenMedia: closeActiveFullscreenMedia
        )
        if intent == .retirement {
            websiteDataCleanup.cancelDeferredAdmissions(for: tab.id)
            if result.isComplete {
                precondition(
                    runtimeTabs.finishRetirementIfDrained(tab.id),
                    "Completed retirement retained a WebView residence"
                )
            }
        }
        return result
    }

    @discardableResult
    func suspendWebViews(for tab: Tab, reason: String) -> Bool {
        guard runtimeTabs.bind(tab).isAccepted else { return false }
        return tabTeardown.suspendWebViews(for: tab, reason: reason)
    }

    func prepareWebKitClose(
        _ webView: WKWebView
    ) -> WebViewWebKitClosePreparation {
        let webViewID = ObjectIdentifier(webView)
        mediaProtection.note(webView)
        websiteDataCleanup.webViewDidLeaveRuntime(webView)

        if protection.schedule(
            .closeWebViewFromWebKit(webViewID: webViewID),
            for: webView,
            reason: "webViewDidClose"
        ).wasScheduled {
            mediaProtection.closeFullscreenMediaIfNeeded(on: webView)
            return .deferred
        }

        return .ready(
            trackedOwner: ownershipQuery.trackedOwner(containing: webView)
        )
    }

    func cleanupTrackedWebViewAfterWebKitClose(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) {
        cleanupTrackedWebView(webView, owner: owner)
    }

    func cleanupTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) {
        processRecovery.cancel(webView)
        trackedRegistration.cleanupTrackedWebView(webView, owner: owner)
    }

    /// Final manager-independent cleanup when the browser runtime disappears
    /// before its windows. No deferred command or detached WebView survives.
    func cleanupAfterBrowserRuntimeDeallocation() {
        runtimeTabs.resetForTerminalShutdown()
        let entries = webViewSessions.takeAllWebViewsForTerminalShutdown()

        replacementPipeline.resetForTerminalShutdown()
        processRecovery.resetForTerminalShutdown()
        deferredProtectedCommands.resetForTerminalShutdown()
        mediaProtection.resetForTerminalShutdown()
        websiteDataCleanup.resetForTerminalShutdown()

        if entries.isEmpty == false {
            let shutdownRuntime = runtimeAssembler.shutdownRuntime()
            for entry in entries {
                SumiWebViewShutdown.performTerminalShutdown(
                    on: entry.webView,
                    runtime: shutdownRuntime
                )
            }
        }

        visibleRuntime.resetWindowRegistrations()

        RuntimeDiagnostics.debug(category: "WebViewLifecycle") {
            "Completed terminal browser-runtime cleanup for \(entries.count) WebView(s)."
        }
    }

    func cleanupUnprotectedTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        tab: Tab?
    ) {
        processRecovery.cancel(webView)
        trackedRegistration.cleanupUnprotectedTrackedWebView(
            webView,
            owner: owner,
            tab: tab
        )
    }

    func tabForPackageCallback(
        _ handle: (any WebRuntimeTabHandle)?
    ) -> Tab? {
        guard let handle,
              let tab = resolveTab(handle.id),
              tab === handle else {
            return nil
        }
        return tab
    }
}
