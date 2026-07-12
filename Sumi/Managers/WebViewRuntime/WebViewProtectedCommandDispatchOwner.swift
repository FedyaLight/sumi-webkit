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
        let webViews: WebViewRuntimeWebViewResolver
        let resolvedTab: @MainActor (UUID) -> Tab?
        let containsWindow: @MainActor (UUID) -> Bool
        let handleWebKitClose: @MainActor (WKWebView) -> Bool
        let executeProfileAssignment: @MainActor (
            UUID,
            UUID?,
            DeferredWebViewProfileAssignmentIntent
        ) -> Bool
        let validateSpaceProfileAssignment: @MainActor (
            DeferredWebViewSpaceProfileAssignmentIntent
        ) -> Bool
        let executeSpaceProfileAssignment: @MainActor (
            DeferredWebViewSpaceProfileAssignmentIntent
        ) -> Bool
        let compositorContainerView: @MainActor (UUID) -> NSView?
        let isRuntimeAvailable: @MainActor () -> Bool
        let removeWebViewFromContainers: @MainActor (WKWebView) -> Bool
        let cleanupTrackedWebView: @MainActor (WKWebView, TrackedWebViewOwner) -> Bool
        let cleanupWindow: @MainActor (UUID) -> Bool
        let cleanupAllWebViews: @MainActor () -> Bool
        let rebuildLiveWebViews: @MainActor (
            Tab,
            UUID?,
            DeferredWebViewRebuildIntent
        ) -> TabWebViewRebuildResult
        let evictHiddenWebViews: @MainActor (UUID, Set<UUID>) -> Bool
        let visibleTabIDSet: @MainActor (UUID) -> Set<UUID>
        let performFallbackWebViewCleanup: @MainActor (WKWebView, UUID) -> Bool
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
        let validationContext = WebViewDeferredProtectedCommandExecutionOwner.ValidationContext(
            resolveWebView: { [dependencies] webViewID in
                dependencies.webViews.resolve(webViewID)
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
                dependencies.resolvedTab(tabID)
            },
            isSpaceProfileAssignmentValid: { [dependencies] intent in
                dependencies.validateSpaceProfileAssignment(intent)
            },
            isRuntimeAvailable: dependencies.isRuntimeAvailable,
            hasCleanupWindowTarget: { [dependencies] windowID in
                dependencies.webViewSessions.trackedWebViews(in: windowID).isEmpty == false
                    || dependencies.compositorContainerView(windowID) != nil
            },
            hasTrackedWebViews: { [dependencies] in
                dependencies.webViewSessions.isTrackingEmpty == false
            },
            hasWindow: { [dependencies] windowID in
                dependencies.containsWindow(windowID)
            }
        )
        return WebViewDeferredProtectedCommandExecutionOwner.Runtime(
            validationContext: validationContext,
            executeCommand: { [weak self] command in
                self?.execute(command) ?? .invalidTarget
            },
            finishCleanupSuppression: { [dependencies] webViewIDs in
                dependencies.finishCleanupSuppression(webViewIDs)
            }
        )
    }

    func execute(
        _ command: DeferredWebViewCommand
    ) -> DeferredProtectedCommandExecutionOutcome {
        switch command {
        case .removeWebViewFromContainers(let webViewID):
            guard let webView = dependencies.webViews.resolve(webViewID) else {
                return .invalidTarget
            }
            return executionOutcome(
                dependencies.removeWebViewFromContainers(webView)
            )
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            guard let webView = dependencies.webViews.resolve(webViewID) else {
                return .invalidTarget
            }
            return executionOutcome(dependencies.cleanupTrackedWebView(
                webView,
                TrackedWebViewOwner(tabID: tabID, windowID: windowID)
            ))
        case .closeWebViewFromWebKit(let webViewID):
            guard let webView = dependencies.webViews.resolve(webViewID) else {
                return .invalidTarget
            }
            guard dependencies.handleWebKitClose(webView) else {
                return .retry
            }
        case .cleanupWindow(let windowID):
            return executionOutcome(dependencies.cleanupWindow(windowID))
        case .cleanupAllWebViews:
            return executionOutcome(dependencies.cleanupAllWebViews())
        case .rebuildLiveWebViews(
            let tabID,
            let preferredPrimaryWindowID,
            let intent
        ):
            guard let tab = resolvedTab(with: tabID) else {
                return .invalidTarget
            }
            let result = dependencies.rebuildLiveWebViews(
                tab,
                preferredPrimaryWindowID,
                intent
            )
            return executionOutcome(result != .failed)
        case .assignProfile(
            let tabID,
            let preferredPrimaryWindowID,
            let intent
        ):
            return executionOutcome(dependencies.executeProfileAssignment(
                tabID,
                preferredPrimaryWindowID,
                intent
            ))
        case .assignSpaceProfile(let intent):
            return executionOutcome(
                dependencies.executeSpaceProfileAssignment(intent)
            )
        case .synchronizeTrackedNavigation(
            let webViewID,
            let tabID,
            let windowID,
            let intent
        ):
            guard let webView = dependencies.webViews.resolve(webViewID),
                  dependencies.webViewSessions.trackedOwner(with: webViewID)
                    == TrackedWebViewOwner(tabID: tabID, windowID: windowID),
                  let tab = resolvedTab(with: tabID),
                  tab.mainFrameLoads.isCurrent(
                      revision: intent.revision,
                      targetURL: intent.targetURL
                  ) else {
                return .invalidTarget
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
                return .executed
            case .submissionFailed:
                return .retry
            case .stale:
                return .invalidTarget
            }
        case .reloadTrackedNavigation(
            let webViewID,
            let tabID,
            let windowID,
            let intent
        ):
            guard let webView = dependencies.webViews.resolve(webViewID),
                  dependencies.webViewSessions.trackedOwner(with: webViewID)
                    == TrackedWebViewOwner(tabID: tabID, windowID: windowID),
                  let tab = resolvedTab(with: tabID),
                  tab.mainFrameLoads.isCurrent(
                      revision: intent.revision,
                      targetURL: intent.targetURL
                  ) else {
                return .invalidTarget
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
                return .executed
            case .submissionFailed:
                return .retry
            case .stale:
                return .invalidTarget
            }
        case .evictHiddenWebViews(let windowID):
            guard dependencies.containsWindow(windowID) else {
                return .invalidTarget
            }
            return executionOutcome(dependencies.evictHiddenWebViews(
                windowID,
                dependencies.visibleTabIDSet(windowID)
            ))
        case .cleanupTabWebView(let webViewID, let tabID):
            guard let webView = dependencies.webViews.resolve(webViewID) else {
                return .invalidTarget
            }
            _ = dependencies.webViewSessions.removeDetachedWebView(webView, for: tabID)
            if let tab = resolvedTab(with: tabID) {
                tab.cleanupCloneWebView(webView)
            } else {
                return executionOutcome(
                    dependencies.performFallbackWebViewCleanup(webView, tabID)
                )
            }
        case .performFallbackWebViewCleanup(let webViewID, let lease):
            guard let webView = dependencies.webViews.resolve(webViewID) else {
                return .invalidTarget
            }
            guard dependencies.webViewSessions.consumePendingCleanup(
                of: webView,
                lease: lease
            ) else {
                return .retry
            }
            if let tab = resolvedTab(with: lease.tabID) {
                tab.cleanupCloneWebView(webView)
            } else {
                return executionOutcome(dependencies.performFallbackWebViewCleanup(
                    webView,
                    lease.tabID
                ))
            }
        }

        return .executed
    }

    private func executionOutcome(
        _ didExecute: Bool
    ) -> DeferredProtectedCommandExecutionOutcome {
        didExecute ? .executed : .retry
    }

    private func resolvedTab(with tabID: UUID) -> Tab? {
        dependencies.resolvedTab(tabID)
    }

    private func tabScopedCleanupValidationContext()
        -> WebViewTabScopedCleanupValidationOwner.Context {
        WebViewTabScopedCleanupValidationOwner.Context(
            resolveWebView: { [dependencies] webViewID in
                dependencies.webViews.resolve(webViewID)
            },
            residence: { [dependencies] webView in
                dependencies.webViewSessions.residence(of: webView)
            }
        )
    }
}
