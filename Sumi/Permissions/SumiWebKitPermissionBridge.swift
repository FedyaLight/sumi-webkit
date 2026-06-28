import Foundation
import WebKit

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

@MainActor
final class SumiWebKitBoolDecisionHandler {
    private var decisionHandler: ((Bool) -> Void)?

    init(_ decisionHandler: @escaping (Bool) -> Void) {
        self.decisionHandler = decisionHandler
    }

    func resolve(_ decision: Bool) {
        guard let handler = decisionHandler else { return }
        decisionHandler = nil
        handler(decision)
    }
}

@MainActor
final class SumiWebKitDisplayCaptureDecisionHandler {
    private var decisionHandler: ((Int) -> Void)?

    init(_ decisionHandler: @escaping (Int) -> Void) {
        self.decisionHandler = decisionHandler
    }

    func resolve(_ decision: SumiWebKitDisplayCapturePermissionDecision) {
        guard let handler = decisionHandler else { return }
        decisionHandler = nil
        handler(decision.rawValue)
    }
}

enum SumiWebKitPermissionPendingCoordinatorRace {
    private enum RaceResult: Sendable {
        case coordinator(SumiPermissionCoordinatorDecision)
        case pendingStrategy(SumiPermissionCoordinatorDecision)
        case timeout(SumiPermissionCoordinatorDecision)
    }

    static func resolve(
        coordinator: any SumiPermissionCoordinating,
        context: SumiPermissionSecurityContext,
        shouldWaitForPromptUI: Bool,
        pendingReason: String,
        timeoutReason: String,
        taskCancelledReason: String,
        noCoordinatorResultReason: String,
        pendingPollIntervalNanoseconds: UInt64,
        coordinatorTimeoutNanoseconds: UInt64,
        temporaryPendingDecision: @escaping @Sendable (
            SumiPermissionSecurityContext,
            String
        ) -> SumiPermissionCoordinatorDecision,
        failClosedDecision: @escaping @Sendable (
            SumiPermissionSecurityContext?,
            String
        ) -> SumiPermissionCoordinatorDecision
    ) async -> SumiPermissionCoordinatorDecision {
        if shouldWaitForPromptUI,
           context.surface == .normalTab {
            return await coordinator.requestPermission(context)
        }

        let pageId = context.request.pageBucketId
        let requestId = context.request.id

        return await withTaskGroup(of: RaceResult.self) { group in
            group.addTask {
                .coordinator(await coordinator.requestPermission(context))
            }
            group.addTask {
                var elapsed: UInt64 = 0
                while elapsed < coordinatorTimeoutNanoseconds {
                    let sleepNanoseconds = min(
                        pendingPollIntervalNanoseconds,
                        coordinatorTimeoutNanoseconds - elapsed
                    )
                    try? await Task.sleep(nanoseconds: sleepNanoseconds)
                    if Task.isCancelled {
                        return .timeout(
                            failClosedDecision(context, taskCancelledReason)
                        )
                    }
                    elapsed += sleepNanoseconds
                    if await coordinator.activeQuery(forPageId: pageId) != nil {
                        await coordinator.cancel(
                            requestId: requestId,
                            reason: pendingReason
                        )
                        return .pendingStrategy(
                            temporaryPendingDecision(context, pendingReason)
                        )
                    }
                }

                await coordinator.cancel(
                    requestId: requestId,
                    reason: timeoutReason
                )
                return .timeout(
                    failClosedDecision(context, timeoutReason)
                )
            }

            guard let result = await group.next() else {
                return failClosedDecision(context, noCoordinatorResultReason)
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

@available(macOS 13.0, *)
@MainActor
final class SumiWebKitPermissionBridge {
    private let coordinator: any SumiPermissionCoordinating
    private let runtimeController: any SumiRuntimePermissionControlling
    private let pendingStrategy: SumiWebKitPermissionBridgePendingStrategy
    private let screenCapturePendingStrategy: SumiWebKitScreenCapturePendingStrategy
    private let pendingPollIntervalNanoseconds: UInt64
    private let coordinatorTimeoutNanoseconds: UInt64
    private let now: @Sendable () -> Date

    init(
        coordinator: any SumiPermissionCoordinating,
        runtimeController: any SumiRuntimePermissionControlling,
        pendingStrategy: SumiWebKitPermissionBridgePendingStrategy = .waitForPromptUI,
        screenCapturePendingStrategy: SumiWebKitScreenCapturePendingStrategy = .waitForPromptUI,
        pendingPollIntervalNanoseconds: UInt64 = 25_000_000,
        coordinatorTimeoutNanoseconds: UInt64 = 500_000_000,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.coordinator = coordinator
        self.runtimeController = runtimeController
        self.pendingStrategy = pendingStrategy
        self.screenCapturePendingStrategy = screenCapturePendingStrategy
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

            let coordinatorDecision = await self.coordinatorDecision(
                for: context,
                shouldWaitForPromptUI: self.pendingStrategy.waitsForPromptUI,
                pendingReason: self.pendingStrategy.reason,
                timeoutReason: "webkit-media-permission-coordinator-timeout"
            )
            let webKitDecision = SumiWebKitMediaCaptureDecisionMapper.webKitDecision(
                for: coordinatorDecision
            )
            guard webKitDecision != .grant || (webView != nil && tabContext.isCurrentPage?() != false) else {
                await self.coordinator.cancel(
                    requestId: context.request.id,
                    reason: "webkit-media-permission-stale-page"
                )
                once.resolve(.deny)
                return
            }
            once.resolve(webKitDecision)

            if coordinatorDecision.outcome == .granted, let webView {
                _ = self.runtimeController.currentRuntimeState(for: webView)
            }
        }
    }

    func handleLegacyMediaCaptureAuthorization(
        _ request: SumiWebKitMediaCaptureRequest,
        tabContext: SumiWebKitMediaCaptureTabContext,
        webView: WKWebView?,
        decisionHandler: @escaping (Bool) -> Void
    ) {
        let once = SumiWebKitBoolDecisionHandler(decisionHandler)
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

            let coordinatorDecision = await self.coordinatorDecision(
                for: context,
                shouldWaitForPromptUI: self.pendingStrategy.waitsForPromptUI,
                pendingReason: self.pendingStrategy.reason,
                timeoutReason: "webkit-media-permission-coordinator-timeout"
            )
            let webKitDecision = SumiWebKitDisplayCaptureDecisionMapper.legacyBoolDecision(
                for: coordinatorDecision
            )
            guard webKitDecision == false || (webView != nil && tabContext.isCurrentPage?() != false) else {
                await self.coordinator.cancel(
                    requestId: context.request.id,
                    reason: "webkit-media-permission-stale-page"
                )
                once.resolve(false)
                return
            }
            once.resolve(webKitDecision)

            if coordinatorDecision.outcome == .granted, let webView {
                _ = self.runtimeController.currentRuntimeState(for: webView)
            }
        }
    }

    func handleDisplayCaptureAuthorization(
        _ request: SumiWebKitDisplayCaptureRequest,
        tabContext: SumiWebKitMediaCaptureTabContext,
        webView: WKWebView?,
        decisionHandler: @escaping (Int) -> Void
    ) {
        let once = SumiWebKitDisplayCaptureDecisionHandler(decisionHandler)
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

            let coordinatorDecision = await self.coordinatorDecision(
                for: context,
                shouldWaitForPromptUI: self.screenCapturePendingStrategy.waitsForPromptUI,
                pendingReason: self.screenCapturePendingStrategy.reason,
                timeoutReason: "webkit-screen-capture-permission-coordinator-timeout"
            )
            let webKitDecision = SumiWebKitDisplayCaptureDecisionMapper.webKitDecision(
                for: coordinatorDecision
            )
            guard webKitDecision != .screenPrompt || (webView != nil && tabContext.isCurrentPage?() != false) else {
                await self.coordinator.cancel(
                    requestId: context.request.id,
                    reason: "webkit-screen-capture-permission-stale-page"
                )
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
        securityContext(
            requestId: request.id,
            requestingOrigin: request.requestingOrigin,
            permissionTypes: request.permissionTypes,
            isMainFrame: request.isMainFrame,
            tabContext: tabContext
        )
    }

    func securityContext(
        for request: SumiWebKitDisplayCaptureRequest,
        tabContext: SumiWebKitMediaCaptureTabContext
    ) -> SumiPermissionSecurityContext {
        securityContext(
            requestId: request.id,
            requestingOrigin: request.requestingOrigin,
            permissionTypes: request.permissionTypes,
            isMainFrame: request.isMainFrame,
            tabContext: tabContext
        )
    }

    private func securityContext(
        requestId: String,
        requestingOrigin: SumiPermissionOrigin,
        permissionTypes: [SumiPermissionType],
        isMainFrame: Bool,
        tabContext: SumiWebKitMediaCaptureTabContext
    ) -> SumiPermissionSecurityContext {
        let topOrigin = SumiPermissionOrigin(
            url: tabContext.committedURL ?? tabContext.mainFrameURL ?? tabContext.visibleURL
        )
        let permissionRequest = SumiPermissionRequest(
            id: requestId,
            tabId: tabContext.tabId,
            pageId: tabContext.pageId,
            frameId: nil,
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            displayDomain: requestingOrigin.displayDomain,
            permissionTypes: permissionTypes,
            hasUserGesture: false,
            requestedAt: now(),
            isEphemeralProfile: tabContext.isEphemeralProfile,
            profilePartitionId: tabContext.profilePartitionId
        )

        return SumiPermissionSecurityContext(
            request: permissionRequest,
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            committedURL: tabContext.committedURL,
            visibleURL: tabContext.visibleURL,
            mainFrameURL: tabContext.mainFrameURL,
            isMainFrame: isMainFrame,
            isActiveTab: tabContext.isActiveTab,
            isVisibleTab: tabContext.isVisibleTab,
            hasUserGesture: nil,
            isEphemeralProfile: tabContext.isEphemeralProfile,
            profilePartitionId: tabContext.profilePartitionId,
            transientPageId: tabContext.pageId,
            surface: tabContext.surface,
            navigationOrPageGeneration: tabContext.navigationOrPageGeneration,
            now: permissionRequest.requestedAt
        )
    }

    private func coordinatorDecision(
        for context: SumiPermissionSecurityContext,
        shouldWaitForPromptUI: Bool,
        pendingReason: String,
        timeoutReason: String
    ) async -> SumiPermissionCoordinatorDecision {
        await SumiWebKitPermissionPendingCoordinatorRace.resolve(
            coordinator: coordinator,
            context: context,
            shouldWaitForPromptUI: shouldWaitForPromptUI,
            pendingReason: pendingReason,
            timeoutReason: timeoutReason,
            taskCancelledReason: "webkit-media-permission-task-cancelled",
            noCoordinatorResultReason: "webkit-media-permission-no-coordinator-result",
            pendingPollIntervalNanoseconds: pendingPollIntervalNanoseconds,
            coordinatorTimeoutNanoseconds: coordinatorTimeoutNanoseconds,
            temporaryPendingDecision: { context, reason in
                SumiWebKitMediaCaptureDecisionMapper.temporaryPendingDecision(
                    for: context,
                    reason: reason
                )
            },
            failClosedDecision: { context, reason in
                SumiWebKitMediaCaptureDecisionMapper.failClosedDecision(
                    for: context,
                    reason: reason
                )
            }
        )
    }
}
