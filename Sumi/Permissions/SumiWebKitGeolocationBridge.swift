import Foundation
import WebKit

enum SumiWebKitGeolocationPendingStrategy: Equatable, Sendable {
    case waitForPromptUI
    case promptPresenterUnavailableDeny

    var reason: String {
        switch self {
        case .waitForPromptUI:
            return "webkit-geolocation-prompt-ui-wait"
        case .promptPresenterUnavailableDeny:
            return "webkit-geolocation-prompt-presenter-unavailable-deny"
        }
    }

    var waitsForPromptUI: Bool {
        self == .waitForPromptUI
    }
}

enum SumiWebKitGeolocationDecisionMapper {
    @available(macOS 12.0, *)
    static func webKitDecision(
        for decision: SumiPermissionCoordinatorDecision
    ) -> WKPermissionDecision {
        decision.outcome == .granted ? .grant : .deny
    }

    static func temporaryPendingDecision(
        for context: SumiPermissionSecurityContext,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .promptRequired,
            state: .ask,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: [.geolocation],
            keys: [context.request.key(for: .geolocation)],
            shouldPersist: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context.isEphemeralProfile
        )
    }

    static func failClosedDecision(
        for context: SumiPermissionSecurityContext?,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .cancelled,
            state: nil,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: [.geolocation],
            keys: context.map { [$0.request.key(for: .geolocation)] } ?? [],
            shouldPersist: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context?.isEphemeralProfile ?? false
        )
    }
}

@MainActor
final class SumiWebKitGeolocationOnce<Decision> {
    private var decisionHandler: ((Decision) -> Void)?

    init(_ decisionHandler: @escaping (Decision) -> Void) {
        self.decisionHandler = decisionHandler
    }

    func resolve(_ decision: Decision) {
        guard let handler = decisionHandler else { return }
        decisionHandler = nil
        handler(decision)
    }
}

@available(macOS 12.0, *)
@MainActor
final class SumiWebKitGeolocationBridge {
    private enum CoordinatorRaceResult: Sendable {
        case coordinator(SumiPermissionCoordinatorDecision)
        case pendingStrategy(SumiPermissionCoordinatorDecision)
        case timeout(SumiPermissionCoordinatorDecision)
    }

    private let coordinator: any SumiPermissionCoordinating
    private weak var geolocationProvider: (any SumiGeolocationProviding)?
    private let pendingStrategy: SumiWebKitGeolocationPendingStrategy
    private let pendingPollIntervalNanoseconds: UInt64
    private let coordinatorTimeoutNanoseconds: UInt64
    private let now: @Sendable () -> Date

    init(
        coordinator: any SumiPermissionCoordinating,
        geolocationProvider: (any SumiGeolocationProviding)?,
        pendingStrategy: SumiWebKitGeolocationPendingStrategy = .waitForPromptUI,
        pendingPollIntervalNanoseconds: UInt64 = 25_000_000,
        coordinatorTimeoutNanoseconds: UInt64 = 500_000_000,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.coordinator = coordinator
        self.geolocationProvider = geolocationProvider
        self.pendingStrategy = pendingStrategy
        self.pendingPollIntervalNanoseconds = pendingPollIntervalNanoseconds
        self.coordinatorTimeoutNanoseconds = coordinatorTimeoutNanoseconds
        self.now = now
    }

    func handleGeolocationAuthorization(
        _ request: SumiWebKitGeolocationRequest,
        tabContext: SumiWebKitGeolocationTabContext,
        webView: WKWebView?,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let once = SumiWebKitGeolocationOnce(decisionHandler)
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
            var webKitDecision = SumiWebKitGeolocationDecisionMapper.webKitDecision(
                for: coordinatorDecision
            )

            if webKitDecision == .grant {
                guard let provider = self.geolocationProvider,
                      provider.isAvailable,
                      webView != nil,
                      tabContext.isCurrentPage?() != false
                else {
                    await self.coordinator.cancel(
                        requestId: context.request.id,
                        reason: "webkit-geolocation-permission-stale-page"
                    )
                    self.geolocationProvider?.cancelAllowedRequest(pageId: tabContext.pageId)
                    webKitDecision = .deny
                    once.resolve(webKitDecision)
                    return
                }
                provider.registerAllowedRequest(
                    pageId: tabContext.pageId,
                    tabId: tabContext.tabId
                )
            }

            once.resolve(webKitDecision)
        }
    }

    func handleLegacyGeolocationAuthorization(
        _ request: SumiWebKitGeolocationRequest,
        tabContext: SumiWebKitGeolocationTabContext,
        webView: WKWebView?,
        decisionHandler: @escaping (Bool) -> Void
    ) {
        let once = SumiWebKitGeolocationOnce(decisionHandler)
        handleGeolocationAuthorization(
            request,
            tabContext: tabContext,
            webView: webView
        ) { decision in
            once.resolve(decision == .grant)
        }
    }

    func securityContext(
        for request: SumiWebKitGeolocationRequest,
        tabContext: SumiWebKitGeolocationTabContext
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
            permissionTypes: [.geolocation],
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
        if pendingStrategy.waitsForPromptUI,
           context.surface == .normalTab,
           context.isActiveTab,
           context.isVisibleTab {
            return await coordinator.requestPermission(context)
        }

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
                            SumiWebKitGeolocationDecisionMapper.failClosedDecision(
                                for: context,
                                reason: "webkit-geolocation-permission-task-cancelled"
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
                            SumiWebKitGeolocationDecisionMapper.temporaryPendingDecision(
                                for: context,
                                reason: pendingStrategy.reason
                            )
                        )
                    }
                }

                await coordinator.cancel(
                    requestId: requestId,
                    reason: "webkit-geolocation-permission-coordinator-timeout"
                )
                return .timeout(
                    SumiWebKitGeolocationDecisionMapper.failClosedDecision(
                        for: context,
                        reason: "webkit-geolocation-permission-coordinator-timeout"
                    )
                )
            }

            guard let result = await group.next() else {
                return SumiWebKitGeolocationDecisionMapper.failClosedDecision(
                    for: context,
                    reason: "webkit-geolocation-permission-no-coordinator-result"
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
