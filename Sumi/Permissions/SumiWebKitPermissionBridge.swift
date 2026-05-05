import Foundation
import WebKit

enum SumiPermissionSiteDecisionError: Error, Equatable, LocalizedError {
    case unavailable
    case unsupportedPermission(String)
    case persistentStoreUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Site permission decisions are unavailable."
        case .unsupportedPermission(let permissionIdentity):
            return "Site permission decisions are unsupported for \(permissionIdentity)."
        case .persistentStoreUnavailable:
            return "Persistent site permission storage is unavailable."
        }
    }
}

protocol SumiPermissionCoordinating: Sendable {
    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision

    func queryPermissionState(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision

    func siteDecisionRecords(
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) async throws -> [SumiPermissionStoreRecord]

    func transientDecisionRecords(
        profilePartitionId: String,
        pageId: String
    ) async throws -> [SumiPermissionStoreRecord]

    func setSiteDecision(
        for key: SumiPermissionKey,
        state: SumiPermissionState,
        source: SumiPermissionDecisionSource,
        reason: String?
    ) async throws

    func resetSiteDecision(
        for key: SumiPermissionKey
    ) async throws

    func resetSiteDecisions(
        for keys: [SumiPermissionKey]
    ) async throws

    @discardableResult
    func resetTransientDecisions(
        profilePartitionId: String,
        pageId: String?,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        reason: String
    ) async -> Int

    func activeQuery(forPageId pageId: String) async -> SumiPermissionAuthorizationQuery?

    func recordPromptShown(queryId: String) async

    func stateSnapshot() async -> SumiPermissionCoordinatorState

    func events() async -> AsyncStream<SumiPermissionCoordinatorEvent>

    @discardableResult
    func approveCurrentAttempt(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func approveOnce(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func approveForSession(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func approvePersistently(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func denyForSession(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func dismiss(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func denyPersistently(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func systemBlock(
        queryId: String,
        snapshots: [SumiSystemPermissionSnapshot],
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func cancel(
        queryId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

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

    @discardableResult
    func cancelProfile(
        profilePartitionId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func cancelSession(
        ownerId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision
}

extension SumiPermissionCoordinator: SumiPermissionCoordinating {}

extension SumiPermissionCoordinating {
    func siteDecisionRecords(
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) async throws -> [SumiPermissionStoreRecord] {
        _ = profilePartitionId
        _ = isEphemeralProfile
        throw SumiPermissionSiteDecisionError.unavailable
    }

    func transientDecisionRecords(
        profilePartitionId: String,
        pageId: String
    ) async throws -> [SumiPermissionStoreRecord] {
        _ = profilePartitionId
        _ = pageId
        return []
    }

    func setSiteDecision(
        for key: SumiPermissionKey,
        state: SumiPermissionState,
        source: SumiPermissionDecisionSource,
        reason: String?
    ) async throws {
        _ = key
        _ = state
        _ = source
        _ = reason
        throw SumiPermissionSiteDecisionError.unavailable
    }

    func resetSiteDecision(
        for key: SumiPermissionKey
    ) async throws {
        _ = key
        throw SumiPermissionSiteDecisionError.unavailable
    }

    func resetSiteDecisions(
        for keys: [SumiPermissionKey]
    ) async throws {
        for key in keys {
            try await resetSiteDecision(for: key)
        }
    }

    @discardableResult
    func resetTransientDecisions(
        profilePartitionId: String,
        pageId: String?,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        reason: String
    ) async -> Int {
        _ = profilePartitionId
        _ = pageId
        _ = requestingOrigin
        _ = topOrigin
        _ = reason
        return 0
    }

    func recordPromptShown(queryId: String) async {
        _ = queryId
    }

    @discardableResult
    func approveCurrentAttempt(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "approve-current-attempt-unavailable")
    }

    @discardableResult
    func approveOnce(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "approve-once-unavailable")
    }

    @discardableResult
    func approveForSession(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "approve-for-session-unavailable")
    }

    @discardableResult
    func approvePersistently(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "approve-persistently-unavailable")
    }

    @discardableResult
    func denyForSession(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "deny-for-session-unavailable")
    }

    @discardableResult
    func dismiss(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "dismiss-unavailable")
    }

    @discardableResult
    func denyPersistently(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "deny-persistently-unavailable")
    }

    @discardableResult
    func systemBlock(
        queryId: String,
        snapshots: [SumiSystemPermissionSnapshot],
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        _ = queryId
        _ = snapshots
        return ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancel(
        queryId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancel(
        requestId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancel(
        pageId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancelNavigation(
        pageId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancelTab(
        tabId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancelProfile(
        profilePartitionId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancelSession(
        ownerId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    private func ignoredSettlementDecision(reason: String) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .ignored,
            state: nil,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: []
        )
    }
}

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
        if shouldWaitForPromptUI,
           (context.surface == .normalTab || context.surface == .miniWindow),
           context.isActiveTab,
           context.isVisibleTab {
            return await coordinator.requestPermission(context)
        }

        let coordinator = coordinator
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
                            reason: pendingReason
                        )
                        return .pendingStrategy(
                            SumiWebKitMediaCaptureDecisionMapper.temporaryPendingDecision(
                                for: context,
                                reason: pendingReason
                            )
                        )
                    }
                }

                await coordinator.cancel(
                    requestId: requestId,
                    reason: timeoutReason
                )
                return .timeout(
                    SumiWebKitMediaCaptureDecisionMapper.failClosedDecision(
                        for: context,
                        reason: timeoutReason
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
