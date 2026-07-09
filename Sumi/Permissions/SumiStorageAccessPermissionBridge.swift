import Foundation
import WebKit

@MainActor
final class SumiStorageAccessCompletionHandler {
    private var completionHandler: ((Bool) -> Void)?

    init(_ completionHandler: @escaping (Bool) -> Void) {
        self.completionHandler = completionHandler
    }

    func resolve(_ granted: Bool) {
        guard let handler = completionHandler else { return }
        completionHandler = nil
        handler(granted)
    }
}

@MainActor
final class SumiStorageAccessPermissionBridge {
    private let coordinator: any SumiPermissionCoordinating
    private let pendingStrategy: SumiStorageAccessPendingStrategy
    private let pendingPollIntervalNanoseconds: UInt64
    private let coordinatorTimeoutNanoseconds: UInt64
    private let now: @Sendable () -> Date
    private let indicatorEventStore: SumiPermissionIndicatorEventStore?

    init(
        coordinator: any SumiPermissionCoordinating,
        pendingStrategy: SumiStorageAccessPendingStrategy = .waitForPromptUI,
        pendingPollIntervalNanoseconds: UInt64 = 25_000_000,
        coordinatorTimeoutNanoseconds: UInt64 = 500_000_000,
        now: @escaping @Sendable () -> Date = { Date() },
        indicatorEventStore: SumiPermissionIndicatorEventStore? = nil
    ) {
        self.coordinator = coordinator
        self.pendingStrategy = pendingStrategy
        self.pendingPollIntervalNanoseconds = pendingPollIntervalNanoseconds
        self.coordinatorTimeoutNanoseconds = coordinatorTimeoutNanoseconds
        self.now = now
        self.indicatorEventStore = indicatorEventStore
    }

    func handleStorageAccessRequest(
        _ request: SumiStorageAccessRequest,
        tabContext: SumiStorageAccessTabContext,
        webView: WKWebView?,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let once = SumiStorageAccessCompletionHandler(completionHandler)
        guard webView != nil else {
            once.resolve(false)
            return
        }

        let context = securityContext(for: request, tabContext: tabContext)
        Task { @MainActor [weak self, weak webView] in
            guard let self else {
                once.resolve(false)
                return
            }

            let decision = await self.coordinatorDecision(for: context)
            self.recordStorageIndicatorEvent(for: decision, context: context)
            let webKitDecision = SumiStorageAccessDecisionMapper.webKitDecision(for: decision)
            guard !webKitDecision || (webView != nil && tabContext.isCurrentPage?() != false) else {
                await self.coordinator.cancel(
                    requestId: context.request.id,
                    reason: "webkit-storage-access-stale-page"
                )
                once.resolve(false)
                return
            }
            once.resolve(webKitDecision)
        }
    }

    func securityContext(
        for request: SumiStorageAccessRequest,
        tabContext: SumiStorageAccessTabContext
    ) -> SumiPermissionSecurityContext {
        SumiPermissionSecurityContextBuilder.make(
            requestId: request.id,
            tabId: tabContext.tabId,
            pageId: tabContext.pageId,
            requestingOrigin: request.requestingOrigin,
            displayDomain: request.requestingOrigin.displayDomain,
            permissionTypes: [.storageAccess],
            hasUserGesture: nil,
            isMainFrame: false,
            committedURL: tabContext.committedURL,
            visibleURL: tabContext.visibleURL,
            mainFrameURL: tabContext.mainFrameURL,
            isActiveTab: tabContext.isActiveTab,
            isVisibleTab: tabContext.isVisibleTab,
            isEphemeralProfile: tabContext.isEphemeralProfile,
            profilePartitionId: tabContext.profilePartitionId,
            surface: tabContext.surface,
            navigationOrPageGeneration: tabContext.navigationOrPageGeneration,
            now: now()
        )
    }

    private func coordinatorDecision(
        for context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        await SumiPermissionPendingCoordinatorRace.resolve(
            coordinator: coordinator,
            context: context,
            shouldWaitForPromptUI: pendingStrategy.waitsForPromptUI,
            pendingReason: pendingStrategy.reason,
            timeoutReason: "webkit-storage-access-coordinator-timeout",
            taskCancelledReason: "webkit-storage-access-task-cancelled",
            noCoordinatorResultReason: "webkit-storage-access-no-coordinator-result",
            pendingPollIntervalNanoseconds: pendingPollIntervalNanoseconds,
            coordinatorTimeoutNanoseconds: coordinatorTimeoutNanoseconds,
            temporaryPendingDecision: { context, reason in
                SumiStorageAccessDecisionMapper.temporaryPendingDecision(
                    for: context,
                    reason: reason
                )
            },
            failClosedDecision: { context, reason in
                SumiStorageAccessDecisionMapper.failClosedDecision(
                    for: context,
                    reason: reason
                )
            }
        )
    }

    private func recordStorageIndicatorEvent(
        for decision: SumiPermissionCoordinatorDecision,
        context: SumiPermissionSecurityContext
    ) {
        guard decision.outcome != .granted,
              decision.outcome != .ignored,
              decision.outcome != .suppressed
        else { return }

        let category: SumiPermissionIndicatorCategory
        let visualStyle: SumiPermissionIndicatorVisualStyle
        let priority: SumiPermissionIndicatorPriority
        switch decision.outcome {
        case .promptRequired:
            category = .pendingRequest
            visualStyle = .attention
            priority = .storageAccessBlockedOrPending
        case .systemBlocked:
            category = .systemBlocked
            visualStyle = .systemWarning
            priority = .systemBlockedSensitive
        case .denied, .unsupported, .requiresUserActivation, .cancelled, .dismissed, .suppressed, .expired:
            category = .blockedEvent
            visualStyle = .blocked
            priority = .storageAccessBlockedOrPending
        case .granted, .ignored:
            return
        }

        indicatorEventStore?.record(
            SumiPermissionIndicatorEventRecord(
                id: "storage-access-\(context.request.id)-\(decision.outcome.rawValue)",
                tabId: context.request.tabId ?? context.request.pageBucketId,
                pageId: context.request.pageBucketId,
                displayDomain: context.request.displayDomain,
                permissionTypes: [.storageAccess],
                category: category,
                visualStyle: visualStyle,
                priority: priority,
                reason: decision.reason,
                requestingOrigin: context.requestingOrigin,
                topOrigin: context.topOrigin,
                profilePartitionId: context.profilePartitionId,
                isEphemeralProfile: context.isEphemeralProfile,
                createdAt: now()
            )
        )
    }
}
