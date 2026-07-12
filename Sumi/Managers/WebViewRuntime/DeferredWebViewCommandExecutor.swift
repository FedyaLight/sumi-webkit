import Foundation
import SumiWebRuntime
import WebKit

/// Executes destructive and maintenance commands that have already passed
/// identity and lifetime validation in `DeferredWebViewCommandAuthority`.
@MainActor
final class DeferredWebViewCleanupExecutor {
    typealias CloseWebView = @MainActor (WKWebView) -> Bool
    typealias RemoveFromContainers = @MainActor (WKWebView) -> Bool
    typealias CleanupTrackedWebView = @MainActor (
        WKWebView,
        TrackedWebViewOwner,
        Tab?
    ) -> Bool
    typealias ShutdownOwnerlessWebView = @MainActor (WKWebView, UUID) -> Void
    typealias FinishRetirementIfDrained = @MainActor (UUID) -> Void

    private let sessions: WebViewSessionRepository
    private let closeWebView: CloseWebView
    private let removeFromContainers: RemoveFromContainers
    private let cleanupTrackedWebView: CleanupTrackedWebView
    private let shutdownOwnerlessWebView: ShutdownOwnerlessWebView
    private let finishRetirementIfDrained: FinishRetirementIfDrained

    init(
        sessions: WebViewSessionRepository,
        closeWebView: @escaping CloseWebView,
        removeFromContainers: @escaping RemoveFromContainers,
        cleanupTrackedWebView: @escaping CleanupTrackedWebView,
        shutdownOwnerlessWebView: @escaping ShutdownOwnerlessWebView,
        finishRetirementIfDrained: @escaping FinishRetirementIfDrained
    ) {
        self.sessions = sessions
        self.closeWebView = closeWebView
        self.removeFromContainers = removeFromContainers
        self.cleanupTrackedWebView = cleanupTrackedWebView
        self.shutdownOwnerlessWebView = shutdownOwnerlessWebView
        self.finishRetirementIfDrained = finishRetirementIfDrained
    }

    func removeFromContainers(_ webView: WKWebView) -> DeferredProtectedCommandExecutionOutcome {
        outcome(removeFromContainers(webView))
    }

    func removeTracked(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        tab: Tab?
    ) -> DeferredProtectedCommandExecutionOutcome {
        guard cleanupTrackedWebView(webView, owner, tab) else { return .retry }
        finishRetirementIfDrained(owner.tabID)
        return .executed
    }

    func closeFromWebKit(_ webView: WKWebView) -> DeferredProtectedCommandExecutionOutcome {
        outcome(closeWebView(webView))
    }

    func cleanDetached(
        _ webView: WKWebView,
        tabID: UUID,
        tab: Tab?
    ) -> DeferredProtectedCommandExecutionOutcome {
        guard sessions.removeDetachedWebView(webView, for: tabID) else {
            return .retry
        }
        if let tab {
            tab.cleanupCloneWebView(webView)
        } else {
            shutdownOwnerlessWebView(webView, tabID)
        }
        finishRetirementIfDrained(tabID)
        return .executed
    }

    func cleanFallback(
        _ webView: WKWebView,
        lease: WebViewPendingCleanupLease,
        tab: Tab?
    ) -> DeferredProtectedCommandExecutionOutcome {
        guard sessions.consumePendingCleanup(of: webView, lease: lease) else {
            return .retry
        }
        if let tab {
            tab.cleanupCloneWebView(webView)
        } else {
            shutdownOwnerlessWebView(webView, lease.tabID)
        }
        finishRetirementIfDrained(lease.tabID)
        return .executed
    }

    private func outcome(_ didExecute: Bool) -> DeferredProtectedCommandExecutionOutcome {
        didExecute ? .executed : .retry
    }
}

/// Executes window-wide cleanup and hidden-view eviction. These operations do
/// not participate in per-WebView residence transitions.
@MainActor
final class DeferredWebViewWindowMaintenanceExecutor {
    typealias CleanupWindow = @MainActor (UUID) -> Bool
    typealias CleanupAllWebViews = @MainActor () -> Bool
    typealias EvictHiddenWebViews = @MainActor (UUID, Set<UUID>) -> Bool
    typealias VisibleTabIDs = @MainActor (UUID) -> Set<UUID>

    private let cleanupWindow: CleanupWindow
    private let cleanupAllWebViews: CleanupAllWebViews
    private let evictHiddenWebViews: EvictHiddenWebViews
    private let visibleTabIDs: VisibleTabIDs

    init(
        cleanupWindow: @escaping CleanupWindow,
        cleanupAllWebViews: @escaping CleanupAllWebViews,
        evictHiddenWebViews: @escaping EvictHiddenWebViews,
        visibleTabIDs: @escaping VisibleTabIDs
    ) {
        self.cleanupWindow = cleanupWindow
        self.cleanupAllWebViews = cleanupAllWebViews
        self.evictHiddenWebViews = evictHiddenWebViews
        self.visibleTabIDs = visibleTabIDs
    }

    func cleanWindow(_ windowID: UUID) -> DeferredProtectedCommandExecutionOutcome {
        outcome(cleanupWindow(windowID))
    }

    func cleanAllWebViews() -> DeferredProtectedCommandExecutionOutcome {
        outcome(cleanupAllWebViews())
    }

    func evictHidden(in windowID: UUID) -> DeferredProtectedCommandExecutionOutcome {
        outcome(evictHiddenWebViews(windowID, visibleTabIDs(windowID)))
    }

    private func outcome(_ didExecute: Bool) -> DeferredProtectedCommandExecutionOutcome {
        didExecute ? .executed : .retry
    }
}

/// Executes rebuild/profile changes. It receives exact live values from the
/// authority and owns no buffering, validation, or retry state.
@MainActor
final class DeferredWebViewConfigurationExecutor {
    typealias Rebuild = @MainActor (
        Tab,
        UUID?,
        DeferredWebViewRebuildIntent
    ) -> TabWebViewRebuildResult
    typealias AssignProfile = @MainActor (
        Tab,
        UUID?,
        DeferredWebViewProfileAssignmentIntent
    ) -> Bool
    typealias AssignSpaceProfile = @MainActor (
        DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool

    private let rebuild: Rebuild
    private let assignProfile: AssignProfile
    private let assignSpaceProfile: AssignSpaceProfile

    init(
        rebuild: @escaping Rebuild,
        assignProfile: @escaping AssignProfile,
        assignSpaceProfile: @escaping AssignSpaceProfile
    ) {
        self.rebuild = rebuild
        self.assignProfile = assignProfile
        self.assignSpaceProfile = assignSpaceProfile
    }

    func rebuild(
        tab: Tab,
        preferredPrimaryWindowID: UUID?,
        intent: DeferredWebViewRebuildIntent
    ) -> DeferredProtectedCommandExecutionOutcome {
        rebuild(tab, preferredPrimaryWindowID, intent) == .failed ? .retry : .executed
    }

    func assignProfile(
        tab: Tab,
        preferredPrimaryWindowID: UUID?,
        intent: DeferredWebViewProfileAssignmentIntent
    ) -> DeferredProtectedCommandExecutionOutcome {
        assignProfile(tab, preferredPrimaryWindowID, intent) ? .executed : .retry
    }

    func assignSpaceProfile(
        intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> DeferredProtectedCommandExecutionOutcome {
        assignSpaceProfile(intent) ? .executed : .retry
    }
}

/// Stateless terminal dispatcher for already-prepared commands.
@MainActor
final class DeferredWebViewCommandExecutor {
    private let cleanup: DeferredWebViewCleanupExecutor
    private let windowMaintenance: DeferredWebViewWindowMaintenanceExecutor
    private let configuration: DeferredWebViewConfigurationExecutor

    init(
        cleanup: DeferredWebViewCleanupExecutor,
        windowMaintenance: DeferredWebViewWindowMaintenanceExecutor,
        configuration: DeferredWebViewConfigurationExecutor
    ) {
        self.cleanup = cleanup
        self.windowMaintenance = windowMaintenance
        self.configuration = configuration
    }

    func execute(
        _ command: DeferredWebViewCommandAuthority.PreparedCommand
    ) -> DeferredProtectedCommandExecutionOutcome {
        switch command {
        case .removeWebViewFromContainers(let webView):
            return cleanup.removeFromContainers(webView)
        case .removeTrackedWebView(let webView, let owner, let tab):
            return cleanup.removeTracked(webView, owner: owner, tab: tab)
        case .closeWebViewFromWebKit(let webView):
            return cleanup.closeFromWebKit(webView)
        case .cleanupWindow(let windowID):
            return windowMaintenance.cleanWindow(windowID)
        case .cleanupAllWebViews:
            return windowMaintenance.cleanAllWebViews()
        case .rebuildLiveWebViews(let tab, let windowID, let intent):
            return configuration.rebuild(
                tab: tab,
                preferredPrimaryWindowID: windowID,
                intent: intent
            )
        case .assignProfile(let tab, let windowID, let intent):
            return configuration.assignProfile(
                tab: tab,
                preferredPrimaryWindowID: windowID,
                intent: intent
            )
        case .assignSpaceProfile(let intent):
            return configuration.assignSpaceProfile(intent: intent)
        case .synchronizeTrackedNavigation(let webView, let tab, _, let intent):
            return executeNavigation(tab: tab, webView: webView, intent: intent) {
                WebRuntimeMainFrameLoader.load(intent.targetURL, on: $0)
            }
        case .reloadTrackedNavigation(let webView, let tab, _, let intent):
            return executeNavigation(tab: tab, webView: webView, intent: intent) {
                WebRuntimeMainFrameReloader.reloadOrLoad(
                    intent.targetURL,
                    on: $0,
                    policy: intent.policy
                )
            }
        case .evictHiddenWebViews(let windowID):
            return windowMaintenance.evictHidden(in: windowID)
        case .cleanupTabWebView(let webView, let tabID, let tab):
            return cleanup.cleanDetached(webView, tabID: tabID, tab: tab)
        case .performFallbackWebViewCleanup(let webView, let lease, let tab):
            return cleanup.cleanFallback(webView, lease: lease, tab: tab)
        }
    }

    private func executeNavigation(
        tab: Tab,
        webView: WKWebView,
        intent: DeferredWebViewNavigationIntent,
        submit: @escaping @MainActor @Sendable (WKWebView) -> WKNavigation?
    ) -> DeferredProtectedCommandExecutionOutcome {
        navigationOutcome(tab.performDeferredMainFrameNavigation(
            on: webView,
            revision: intent.revision,
            targetURL: intent.targetURL,
            performLoad: submit
        ))
    }

    private func executeNavigation(
        tab: Tab,
        webView: WKWebView,
        intent: DeferredWebViewReloadIntent,
        submit: @escaping @MainActor @Sendable (WKWebView) -> WKNavigation?
    ) -> DeferredProtectedCommandExecutionOutcome {
        navigationOutcome(tab.performDeferredMainFrameNavigation(
            on: webView,
            revision: intent.revision,
            targetURL: intent.targetURL,
            performLoad: submit
        ))
    }

    private func navigationOutcome(
        _ claim: TabDeferredMainFrameLoadClaim
    ) -> DeferredProtectedCommandExecutionOutcome {
        switch claim {
        case .claimed, .alreadyScheduled:
            return .executed
        case .submissionFailed:
            return .retry
        case .stale:
            return .invalidTarget
        }
    }
}
