import Foundation
import WebKit

protocol SumiPermissionCoordinating: Sendable {
    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision

    func queryPermissionState(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision

    func activeQuery(forPageId pageId: String) async -> SumiPermissionAuthorizationQuery?

    @discardableResult
    func cancel(
        requestId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func cancel(
        pageId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func cancelNavigation(
        pageId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func cancelTab(
        tabId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision
}

extension SumiPermissionCoordinator: SumiPermissionCoordinating {}

@available(macOS 13.0, *)
@MainActor
final class SumiWebKitPermissionDecisionHandler {
    private var decisionHandler: ((WKPermissionDecision) -> Void)?

    init(_ decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        self.decisionHandler = decisionHandler
    }

    func resolve(_ decision: WKPermissionDecision) {
        guard let handler = decisionHandler else { return }
        decisionHandler = nil
        handler(decision)
    }
}

@available(macOS 13.0, *)
@MainActor
final class SumiWebKitPermissionBridge {
    private enum CoordinatorRaceResult: Sendable {
        case coordinator(SumiPermissionCoordinatorDecision)
        case pendingStrategy(SumiPermissionCoordinatorDecision)
        case timeout(SumiPermissionCoordinatorDecision)
    }

    private let coordinator: any SumiPermissionCoordinating
    private let runtimeController: any SumiRuntimePermissionControlling
    private let pendingStrategy: SumiWebKitPermissionBridgePendingStrategy
    private let pendingPollIntervalNanoseconds: UInt64
    private let coordinatorTimeoutNanoseconds: UInt64
    private let now: @Sendable () -> Date

    init(
        coordinator: any SumiPermissionCoordinating,
        runtimeController: any SumiRuntimePermissionControlling,
        pendingStrategy: SumiWebKitPermissionBridgePendingStrategy = .denyUntilPromptUIExists,
        pendingPollIntervalNanoseconds: UInt64 = 25_000_000,
        coordinatorTimeoutNanoseconds: UInt64 = 500_000_000,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.coordinator = coordinator
        self.runtimeController = runtimeController
        self.pendingStrategy = pendingStrategy
        self.pendingPollIntervalNanoseconds = pendingPollIntervalNanoseconds
        self.coordinatorTimeoutNanoseconds = coordinatorTimeoutNanoseconds
        self.now = now
    }

    func handleMediaCaptureAuthorization(
        _ request: SumiWebKitMediaCaptureRequest,
        tabContext: SumiWebKitMediaCaptureTabContext,
        webView: WKWebView?,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let once = SumiWebKitPermissionDecisionHandler(decisionHandler)
        guard webView != nil else {
            once.resolve(.deny)
            return
        }

        let context = securityContext(for: request, tabContext: tabContext)

        Task { @MainActor [weak self, weak webView] in
            guard let self else {
                once.resolve(.deny)
                return
            }

            let coordinatorDecision = await self.coordinatorDecision(for: context)
            let webKitDecision = SumiWebKitMediaCaptureDecisionMapper.webKitDecision(
                for: coordinatorDecision
            )
            guard webKitDecision != .grant || webView != nil else {
                once.resolve(.deny)
                return
            }
            once.resolve(webKitDecision)

            if coordinatorDecision.outcome == .granted, let webView {
                _ = self.runtimeController.currentRuntimeState(for: webView)
            }
        }
    }

    func securityContext(
        for request: SumiWebKitMediaCaptureRequest,
        tabContext: SumiWebKitMediaCaptureTabContext
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
            permissionTypes: request.permissionTypes,
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
            isMainFrame: request.isMainFrame,
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
                            SumiWebKitMediaCaptureDecisionMapper.failClosedDecision(
                                for: context,
                                reason: "webkit-media-permission-task-cancelled"
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
                            SumiWebKitMediaCaptureDecisionMapper.temporaryPendingDecision(
                                for: context,
                                reason: pendingStrategy.reason
                            )
                        )
                    }
                }

                await coordinator.cancel(
                    requestId: requestId,
                    reason: "webkit-media-permission-coordinator-timeout"
                )
                return .timeout(
                    SumiWebKitMediaCaptureDecisionMapper.failClosedDecision(
                        for: context,
                        reason: "webkit-media-permission-coordinator-timeout"
                    )
                )
            }

            guard let result = await group.next() else {
                return SumiWebKitMediaCaptureDecisionMapper.failClosedDecision(
                    for: context,
                    reason: "webkit-media-permission-no-coordinator-result"
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
