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
        SumiPermissionFailClosedMapper.temporaryPendingDecision(
            for: context,
            reason: reason,
            permissionTypes: [.geolocation]
        )
    }

    static func failClosedDecision(
        for context: SumiPermissionSecurityContext?,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionFailClosedMapper.failClosedDecision(
            for: context,
            reason: reason,
            permissionTypes: [.geolocation]
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
        SumiPermissionSecurityContextBuilder.make(
            requestId: request.id,
            tabId: tabContext.tabId,
            pageId: tabContext.pageId,
            requestingOrigin: request.requestingOrigin,
            displayDomain: request.requestingOrigin.displayDomain,
            permissionTypes: [.geolocation],
            hasUserGesture: nil,
            isMainFrame: request.isMainFrame,
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
            timeoutReason: "webkit-geolocation-permission-coordinator-timeout",
            taskCancelledReason: "webkit-geolocation-permission-task-cancelled",
            noCoordinatorResultReason: "webkit-geolocation-permission-no-coordinator-result",
            pendingPollIntervalNanoseconds: pendingPollIntervalNanoseconds,
            coordinatorTimeoutNanoseconds: coordinatorTimeoutNanoseconds,
            temporaryPendingDecision: { context, reason in
                SumiWebKitGeolocationDecisionMapper.temporaryPendingDecision(
                    for: context,
                    reason: reason
                )
            },
            failClosedDecision: { context, reason in
                SumiWebKitGeolocationDecisionMapper.failClosedDecision(
                    for: context,
                    reason: reason
                )
            }
        )
    }
}
