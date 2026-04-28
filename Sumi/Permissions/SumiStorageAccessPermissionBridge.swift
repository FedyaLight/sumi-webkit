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
    private enum CoordinatorRaceResult: Sendable {
        case coordinator(SumiPermissionCoordinatorDecision)
        case pendingStrategy(SumiPermissionCoordinatorDecision)
        case timeout(SumiPermissionCoordinatorDecision)
    }

    private let coordinator: any SumiPermissionCoordinating
    private let pendingStrategy: SumiStorageAccessPendingStrategy
    private let pendingPollIntervalNanoseconds: UInt64
    private let coordinatorTimeoutNanoseconds: UInt64
    private let now: @Sendable () -> Date

    init(
        coordinator: any SumiPermissionCoordinating,
        pendingStrategy: SumiStorageAccessPendingStrategy = .denyUntilPromptUIExists,
        pendingPollIntervalNanoseconds: UInt64 = 25_000_000,
        coordinatorTimeoutNanoseconds: UInt64 = 500_000_000,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.coordinator = coordinator
        self.pendingStrategy = pendingStrategy
        self.pendingPollIntervalNanoseconds = pendingPollIntervalNanoseconds
        self.coordinatorTimeoutNanoseconds = coordinatorTimeoutNanoseconds
        self.now = now
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
            guard webView != nil else {
                once.resolve(false)
                return
            }
            once.resolve(SumiStorageAccessDecisionMapper.webKitDecision(for: decision))
        }
    }

    func securityContext(
        for request: SumiStorageAccessRequest,
        tabContext: SumiStorageAccessTabContext
    ) -> SumiPermissionSecurityContext {
        let topOrigin = SumiPermissionOrigin(
            url: tabContext.committedURL ?? tabContext.mainFrameURL ?? tabContext.visibleURL
        )
        let permissionRequest = SumiPermissionRequest(
            id: request.id,
            tabId: tabContext.tabId,
            pageId: tabContext.pageId,
            frameId: nil,
            requestingOrigin: request.requestingOrigin,
            topOrigin: topOrigin,
            displayDomain: request.requestingOrigin.displayDomain,
            permissionTypes: [.storageAccess],
            hasUserGesture: false,
            requestedAt: now(),
            isEphemeralProfile: tabContext.isEphemeralProfile,
            profilePartitionId: tabContext.profilePartitionId
        )

        return SumiPermissionSecurityContext(
            request: permissionRequest,
            requestingOrigin: request.requestingOrigin,
            topOrigin: topOrigin,
            committedURL: tabContext.committedURL,
            visibleURL: tabContext.visibleURL,
            mainFrameURL: tabContext.mainFrameURL,
            isMainFrame: false,
            isActiveTab: tabContext.isActiveTab,
            isVisibleTab: tabContext.isVisibleTab,
            hasUserGesture: nil,
            isEphemeralProfile: tabContext.isEphemeralProfile,
            profilePartitionId: tabContext.profilePartitionId,
            transientPageId: tabContext.pageId,
            surface: .normalTab,
            navigationOrPageGeneration: tabContext.navigationOrPageGeneration,
            now: permissionRequest.requestedAt
        )
    }

    private func coordinatorDecision(
        for context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        let coordinator = coordinator
        let pendingStrategy = pendingStrategy
        let pollInterval = pendingPollIntervalNanoseconds
        let timeout = coordinatorTimeoutNanoseconds
        let pageId = context.request.pageBucketId
        let requestId = context.request.id

        return await withTaskGroup(of: CoordinatorRaceResult.self) { group in
            group.addTask {
                .coordinator(await coordinator.requestPermission(context))
            }
            group.addTask {
                var elapsed: UInt64 = 0
                while elapsed < timeout {
                    let sleepNanoseconds = min(pollInterval, timeout - elapsed)
                    try? await Task.sleep(nanoseconds: sleepNanoseconds)
                    if Task.isCancelled {
                        return .timeout(
                            SumiStorageAccessDecisionMapper.failClosedDecision(
                                for: context,
                                reason: "webkit-storage-access-task-cancelled"
                            )
                        )
                    }
                    elapsed += sleepNanoseconds
                    if await coordinator.activeQuery(forPageId: pageId) != nil {
                        await coordinator.cancel(
                            requestId: requestId,
                            reason: pendingStrategy.reason
                        )
                        return .pendingStrategy(
                            SumiStorageAccessDecisionMapper.temporaryPendingDecision(
                                for: context,
                                reason: pendingStrategy.reason
                            )
                        )
                    }
                }

                await coordinator.cancel(
                    requestId: requestId,
                    reason: "webkit-storage-access-coordinator-timeout"
                )
                return .timeout(
                    SumiStorageAccessDecisionMapper.failClosedDecision(
                        for: context,
                        reason: "webkit-storage-access-coordinator-timeout"
                    )
                )
            }

            guard let result = await group.next() else {
                return SumiStorageAccessDecisionMapper.failClosedDecision(
                    for: context,
                    reason: "webkit-storage-access-no-coordinator-result"
                )
            }
            group.cancelAll()

            switch result {
            case .coordinator(let decision),
                 .pendingStrategy(let decision),
                 .timeout(let decision):
                return decision
            }
        }
    }
}
