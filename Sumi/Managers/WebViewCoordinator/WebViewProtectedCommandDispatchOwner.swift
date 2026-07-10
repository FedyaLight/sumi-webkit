import AppKit
import Foundation
import SumiWebRuntime
import WebKit

/// Routes WebView mutations that arrive while a WebView is protected from
/// compositor changes (fullscreen media, history swipe, visual handoff):
/// enqueues them as deferred commands, prunes invalidated ones, and executes
/// them once protection lifts.
@MainActor
final class WebViewProtectedCommandDispatchOwner {
    struct Dependencies {
        let mediaProtectionOwner: WebViewMediaProtectionOwner
        let executionOwner: WebViewDeferredProtectedCommandExecutionOwner
        let tabScopedCleanupValidationOwner: WebViewTabScopedCleanupValidationOwner
        let webViewSessions: WebViewSessionRepository
        let requireBrowserRuntimeContext: @MainActor () -> WebViewCoordinatorBrowserRuntimeContext
        let resolveWebView: @MainActor (ObjectIdentifier) -> WKWebView?
        let resolvedTab: @MainActor (UUID, WebViewCoordinatorBrowserRuntimeContext) -> Tab?
        let compositorContainerView: @MainActor (UUID) -> NSView?
        let removeWebViewFromContainers: @MainActor (WKWebView) -> Void
        let cleanupTrackedWebView: @MainActor (WKWebView, TrackedWebViewOwner) -> Void
        let cleanupWindow: @MainActor (UUID) -> Void
        let cleanupAllWebViews: @MainActor () -> Void
        let rebuildLiveWebViews: @MainActor (
            Tab,
            UUID?,
            DeferredWebViewRebuildIntent
        ) -> TabWebViewRebuildResult
        let evictHiddenWebViews: @MainActor (UUID, Set<UUID>) -> Void
        let visibleTabIDSet: @MainActor (UUID) -> Set<UUID>
        let performFallbackWebViewCleanup: @MainActor (WKWebView, UUID) -> Void
        let finishCleanupSuppression: @MainActor ([ObjectIdentifier]) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func enqueue(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String
    ) -> Bool {
        schedule(command, for: webView, reason: reason).wasScheduled
    }

    func schedule(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String
    ) -> DeferredProtectedCommandSchedulingOutcome {
        dependencies.mediaProtectionOwner.note(webView)
        guard dependencies.mediaProtectionOwner.isProtected(webView) else {
            return .notProtected
        }

        return dependencies.executionOwner.schedule(
            command,
            for: webView,
            reason: reason,
            mediaProtectionOwner: dependencies.mediaProtectionOwner,
            runtime: executionRuntime()
        )
    }

    func flushCommands(for webViewID: ObjectIdentifier) {
        guard dependencies.mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID) else {
            return
        }
        dependencies.executionOwner.flushCommandsIfUnprotected(
            for: webViewID,
            mediaProtectionOwner: dependencies.mediaProtectionOwner,
            runtime: executionRuntime()
        )
    }

    func pruneInvalidCommands(reason: String) {
        guard dependencies.mediaProtectionOwner.hasDeferredProtectedCommands else { return }
        dependencies.executionOwner.pruneInvalidCommands(
            reason: reason,
            mediaProtectionOwner: dependencies.mediaProtectionOwner,
            runtime: executionRuntime()
        )
    }

    // MARK: - Execution

    private func executionRuntime() -> WebViewDeferredProtectedCommandExecutionOwner.Runtime {
        let runtimeContext = dependencies.requireBrowserRuntimeContext()
        let validationContext = WebViewDeferredProtectedCommandExecutionOwner.ValidationContext(
            resolveWebView: { [dependencies] webViewID in
                dependencies.resolveWebView(webViewID)
            },
            resolveTrackedOwner: { [dependencies] webViewID in
                dependencies.webViewSessions.trackedOwner(with: webViewID)
            },
            canCleanUpDetachedWebView: { [self] webViewID, tabID in
                dependencies.tabScopedCleanupValidationOwner.canCleanUpDetachedWebView(
                    with: webViewID,
                    tabID: tabID,
                    context: tabScopedCleanupValidationContext()
                )
            },
            canPerformFallbackWebViewCleanup: { [self] webViewID, lease in
                dependencies.tabScopedCleanupValidationOwner.canPerformFallbackCleanup(
                    with: webViewID,
                    lease: lease,
                    context: tabScopedCleanupValidationContext()
                )
            },
            resolveTab: { [dependencies] tabID in
                dependencies.resolvedTab(tabID, runtimeContext)
            },
            isSpaceProfileAssignmentValid: { intent in
                runtimeContext.validateDeferredSpaceProfileAssignment(intent)
            },
            hasTabManager: {
                true
            },
            hasCleanupWindowTarget: { [dependencies] windowID in
                dependencies.webViewSessions.trackedWebViews(in: windowID).isEmpty == false
                    || dependencies.compositorContainerView(windowID) != nil
            },
            hasTrackedWebViews: { [dependencies] in
                dependencies.webViewSessions.isTrackingEmpty == false
            },
            hasWindow: { windowID in
                runtimeContext.window(windowID) != nil
            }
        )
        return WebViewDeferredProtectedCommandExecutionOwner.Runtime(
            validationContext: validationContext,
            executeCommand: { [weak self] command in
                self?.execute(command) ?? false
            },
            finishCleanupSuppression: { [dependencies] webViewIDs in
                dependencies.finishCleanupSuppression(webViewIDs)
            }
        )
    }

    @discardableResult
    func execute(_ command: DeferredWebViewCommand) -> Bool {
        switch command {
        case .removeWebViewFromContainers(let webViewID):
            guard let webView = dependencies.resolveWebView(webViewID) else {
                return false
            }
            dependencies.removeWebViewFromContainers(webView)
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            guard let webView = dependencies.resolveWebView(webViewID) else {
                return false
            }
            dependencies.cleanupTrackedWebView(
                webView,
                TrackedWebViewOwner(tabID: tabID, windowID: windowID)
            )
        case .closeWebViewFromWebKit(let webViewID):
            guard let webView = dependencies.resolveWebView(webViewID) else {
                return false
            }
            guard dependencies.requireBrowserRuntimeContext()
                .handleUnprotectedWebViewDidClose(webView) else {
                return false
            }
        case .cleanupWindow(let windowID):
            dependencies.cleanupWindow(windowID)
        case .cleanupAllWebViews:
            dependencies.cleanupAllWebViews()
        case .rebuildLiveWebViews(
            let tabID,
            let preferredPrimaryWindowID,
            let intent
        ):
            guard let tab = resolvedTab(with: tabID) else {
                return false
            }
            let result = dependencies.rebuildLiveWebViews(
                tab,
                preferredPrimaryWindowID,
                intent
            )
            return result != .failed
        case .assignProfile(
            let tabID,
            let preferredPrimaryWindowID,
            let intent
        ):
            return dependencies.requireBrowserRuntimeContext()
                .executeDeferredProfileAssignment(
                    tabID,
                    preferredPrimaryWindowID,
                    intent
                )
        case .assignSpaceProfile(let intent):
            return dependencies.requireBrowserRuntimeContext()
                .executeDeferredSpaceProfileAssignment(intent)
        case .synchronizeTrackedNavigation(
            let webViewID,
            let tabID,
            let windowID,
            let intent
        ):
            guard let webView = dependencies.resolveWebView(webViewID),
                  dependencies.webViewSessions.trackedOwner(with: webViewID)
                    == TrackedWebViewOwner(tabID: tabID, windowID: windowID),
                  let tab = resolvedTab(with: tabID),
                  tab.isCurrentMainFrameNavigationIntent(
                      revision: intent.revision,
                      targetURL: intent.targetURL
                  ) else {
                return false
            }
            let claim = tab.performDeferredMainFrameNavigation(
                on: webView,
                revision: intent.revision,
                targetURL: intent.targetURL
            ) {
                WebRuntimeMainFrameLoader.load(intent.targetURL, on: $0)
            }
            switch claim {
            case .claimed, .alreadyScheduled:
                return true
            case .submissionFailed, .stale:
                return false
            }
        case .reloadTrackedNavigation(
            let webViewID,
            let tabID,
            let windowID,
            let intent
        ):
            guard let webView = dependencies.resolveWebView(webViewID),
                  dependencies.webViewSessions.trackedOwner(with: webViewID)
                    == TrackedWebViewOwner(tabID: tabID, windowID: windowID),
                  let tab = resolvedTab(with: tabID),
                  tab.isCurrentMainFrameNavigationIntent(
                      revision: intent.revision,
                      targetURL: intent.targetURL
                  ) else {
                return false
            }
            let claim = tab.performDeferredMainFrameNavigation(
                on: webView,
                revision: intent.revision,
                targetURL: intent.targetURL
            ) {
                WebRuntimeMainFrameReloader.reloadOrLoad(
                    intent.targetURL,
                    on: $0,
                    policy: intent.policy
                )
            }
            switch claim {
            case .claimed, .alreadyScheduled:
                return true
            case .submissionFailed, .stale:
                return false
            }
        case .evictHiddenWebViews(let windowID):
            let runtimeContext = dependencies.requireBrowserRuntimeContext()
            guard runtimeContext.window(windowID) != nil
            else {
                return false
            }
            dependencies.evictHiddenWebViews(
                windowID,
                dependencies.visibleTabIDSet(windowID)
            )
        case .cleanupTabWebView(let webViewID, let tabID):
            guard let webView = dependencies.resolveWebView(webViewID) else {
                return false
            }
            _ = dependencies.webViewSessions.removeDetachedWebView(webView, for: tabID)
            if let tab = resolvedTab(with: tabID) {
                tab.cleanupCloneWebView(webView)
            } else {
                dependencies.performFallbackWebViewCleanup(webView, tabID)
            }
        case .performFallbackWebViewCleanup(let webViewID, let lease):
            guard let webView = dependencies.resolveWebView(webViewID) else {
                return false
            }
            guard dependencies.webViewSessions.consumePendingCleanup(
                of: webView,
                lease: lease
            ) else {
                return false
            }
            if let tab = resolvedTab(with: lease.tabID) {
                tab.cleanupCloneWebView(webView)
            } else {
                dependencies.performFallbackWebViewCleanup(webView, lease.tabID)
            }
        }

        return true
    }

    private func resolvedTab(with tabID: UUID) -> Tab? {
        dependencies.resolvedTab(tabID, dependencies.requireBrowserRuntimeContext())
    }

    private func tabScopedCleanupValidationContext()
        -> WebViewTabScopedCleanupValidationOwner.Context {
        WebViewTabScopedCleanupValidationOwner.Context(
            resolveWebView: { [dependencies] webViewID in
                dependencies.resolveWebView(webViewID)
            },
            residence: { [dependencies] webView in
                dependencies.webViewSessions.residence(of: webView)
            }
        )
    }
}

extension WebViewProtectedCommandDispatchOwner.Dependencies {
    @MainActor
    static func live(coordinator: WebViewCoordinator) -> Self {
        Self(
            mediaProtectionOwner: coordinator.mediaProtectionOwner,
            executionOwner: coordinator.deferredProtectedCommandExecutionOwner,
            tabScopedCleanupValidationOwner: coordinator.tabScopedCleanupValidationOwner,
            webViewSessions: coordinator.webViewSessions,
            requireBrowserRuntimeContext: { [weak coordinator] in
                guard let coordinator else {
                    preconditionFailure("WebViewCoordinator dependency used after deallocation")
                }
                return coordinator.runtimeContextStore.requireBrowser()
            },
            resolveWebView: { [weak coordinator] webViewID in
                coordinator?.protectionRuntime.resolveWebView(with: webViewID)
            },
            resolvedTab: { [weak coordinator] tabID, runtimeContext in
                coordinator?.runtimeTabs.resolve(
                    tabID,
                    runtime: runtimeContext
                )
            },
            compositorContainerView: { [weak coordinator] windowID in
                coordinator?.compositorRuntime.containerView(for: windowID)
            },
            removeWebViewFromContainers: { [weak coordinator] webView in
                coordinator?.compositorRuntime.removeWebViewFromContainers(webView)
            },
            cleanupTrackedWebView: { [weak coordinator] webView, owner in
                coordinator?.lifecycleService.cleanupTrackedWebView(
                    webView,
                    owner: owner
                )
            },
            cleanupWindow: { [weak coordinator] windowID in
                coordinator?.lifecycleService.cleanupWindow(windowID)
            },
            cleanupAllWebViews: { [weak coordinator] in
                coordinator?.lifecycleService.cleanupAllWebViews()
            },
            rebuildLiveWebViews: {
                [weak coordinator]
                tab, preferredPrimaryWindowId, intent in
                guard let coordinator else { return .failed }
                return coordinator.rebuildService.rebuildLiveWebViewsResult(
                    for: tab,
                    preferredPrimaryWindowID: preferredPrimaryWindowId,
                    load: intent.targetURL,
                    configuration: intent.configuration,
                    reason: "WebViewRebuildService.deferredRebuildLiveWebViews",
                    intentRevision: intent.revision,
                    rebuildKind: intent.kind
                )
            },
            evictHiddenWebViews: { [weak coordinator] windowID, visibleTabIDs in
                coordinator?.visibilityRuntime.evictHiddenWebViewsIfNeeded(
                    in: windowID,
                    visibleTabIDs: visibleTabIDs
                )
            },
            visibleTabIDSet: { [weak coordinator] windowID in
                coordinator?.visibilityRuntime.visibleTabIDs(in: windowID) ?? []
            },
            performFallbackWebViewCleanup: { [weak coordinator] webView, tabID in
                coordinator?.physicalCleanupService.clean(webView, tabID: tabID)
            },
            finishCleanupSuppression: { [weak coordinator] webViewIDs in
                coordinator?.protectionRuntime
                    .finishCleanupSuppression(for: webViewIDs)
            }
        )
    }
}
