import Foundation

enum SumiExternalSchemePermissionEvent: Equatable, Sendable {
    case attempted(requestId: String, pageId: String, classification: SumiExternalSchemeClassification)
    case opened(requestId: String, pageId: String, scheme: String)
    case blockedByDefault(requestId: String, pageId: String, reason: String)
    case blockedByStoredDeny(requestId: String, pageId: String, reason: String)
    case blockedPromptPresenterUnavailable(requestId: String, pageId: String, reason: String)
    case unsupportedScheme(requestId: String, pageId: String, reason: String)
    case openFailed(requestId: String, pageId: String, reason: String)
    case possibleAbuse(requestId: String, pageId: String, attemptCount: Int)
}

@MainActor
final class SumiExternalSchemePermissionBridge {
    typealias EventSink = @MainActor (SumiExternalSchemePermissionEvent) -> Void

    private let coordinator: any SumiPermissionCoordinating
    private let appResolver: any SumiExternalAppResolving
    let sessionStore: SumiExternalSchemeSessionStore
    private let pendingStrategy: SumiExternalSchemePendingStrategy
    private let now: @Sendable () -> Date
    private let eventSink: EventSink?

    init(
        coordinator: any SumiPermissionCoordinating,
        appResolver: (any SumiExternalAppResolving)? = nil,
        sessionStore: SumiExternalSchemeSessionStore? = nil,
        pendingStrategy: SumiExternalSchemePendingStrategy = .waitForPromptUI,
        now: @escaping @Sendable () -> Date = { Date() },
        eventSink: EventSink? = nil
    ) {
        self.coordinator = coordinator
        self.appResolver = appResolver ?? SumiNSWorkspaceExternalAppResolver.shared
        self.sessionStore = sessionStore ?? SumiExternalSchemeSessionStore()
        self.pendingStrategy = pendingStrategy
        self.now = now
        self.eventSink = eventSink
    }

    func evaluate(
        _ request: SumiExternalSchemePermissionRequest,
        tabContext: SumiExternalSchemePermissionTabContext,
        willOpen: @MainActor () -> Void = {}
    ) async -> SumiExternalSchemePermissionResult {
        emit(.attempted(
            requestId: request.id,
            pageId: tabContext.pageId,
            classification: request.classification
        ))

        guard request.classification != .internalOrBrowserOwned else {
            return finish(
                request,
                tabContext: tabContext,
                result: .unsupportedScheme,
                reason: "external-scheme-internal-browser-scheme"
            )
        }

        guard let targetURL = request.targetURL,
              SumiExternalSchemePermissionRequest.isValidExternalSchemeURL(targetURL),
              !request.normalizedScheme.isEmpty
        else {
            return finish(
                request,
                tabContext: tabContext,
                result: .unsupportedScheme,
                reason: "external-scheme-invalid-url-or-scheme"
            )
        }

        guard appResolver.appInfo(for: targetURL) != nil else {
            return finish(
                request,
                tabContext: tabContext,
                result: .unsupportedScheme,
                reason: "external-scheme-no-installed-handler"
            )
        }

        guard request.requestingOrigin.isWebOrigin,
              topOrigin(for: tabContext).isWebOrigin
        else {
            return finish(
                request,
                tabContext: tabContext,
                result: .blockedByDefault,
                reason: "external-scheme-origin-not-keyable"
            )
        }

        let context = securityContext(
            for: request,
            tabContext: tabContext,
            bypassActivationGateForStoreLookup: true
        )
        let coordinatorDecision = await coordinator.queryPermissionState(context)
        let result = SumiExternalSchemeDecisionMapper.resultKind(
            for: coordinatorDecision,
            request: request
        )

        switch result {
        case .opened:
            guard tabContext.isCurrentPage?() != false else {
                return finish(
                    request,
                    tabContext: tabContext,
                    result: .blockedPromptPresenterUnavailable,
                    reason: "external-scheme-stale-page"
                )
            }
            willOpen()
            guard appResolver.open(targetURL) else {
                return finish(
                    request,
                    tabContext: tabContext,
                    result: .openFailed,
                    reason: "external-scheme-open-failed"
                )
            }
            return finish(
                request,
                tabContext: tabContext,
                result: .opened,
                reason: coordinatorDecision.reason
            )

        case .blockedPromptPresenterUnavailable:
            if pendingStrategy.waitsForPromptUI,
               request.isUserActivated,
               tabContext.isActiveTab,
               tabContext.isVisibleTab {
                let promptContext = securityContext(
                    for: request,
                    tabContext: tabContext,
                    bypassActivationGateForStoreLookup: false
                )
                let settlementDecision = await coordinator.requestPermission(promptContext)
                let settlementResult = SumiExternalSchemeDecisionMapper.resultKind(
                    for: settlementDecision,
                    request: request
                )
                if settlementResult == .opened {
                    guard tabContext.isCurrentPage?() != false else {
                        await coordinator.cancel(
                            requestId: promptContext.request.id,
                            reason: "external-scheme-stale-page"
                        )
                        return finish(
                            request,
                            tabContext: tabContext,
                            result: .blockedPromptPresenterUnavailable,
                            reason: "external-scheme-stale-page"
                        )
                    }
                    willOpen()
                    guard appResolver.open(targetURL) else {
                        return finish(
                        request,
                        tabContext: tabContext,
                        result: .openFailed,
                        reason: "external-scheme-open-failed"
                        )
                    }
                    return finish(
                        request,
                        tabContext: tabContext,
                        result: .opened,
                        reason: settlementDecision.reason
                    )
                }

                return finish(
                    request,
                    tabContext: tabContext,
                    result: settlementResult,
                    reason: settlementDecision.reason
                )
            }

            return finish(
                request,
                tabContext: tabContext,
                result: .blockedPromptPresenterUnavailable,
                reason: pendingStrategy.reason
            )

        case .blockedByDefault where coordinatorDecision.outcome == .promptRequired:
            return finish(
                request,
                tabContext: tabContext,
                result: .blockedByDefault,
                reason: "external-scheme-background-default-block"
            )

        case .blockedByStoredDeny, .blockedByDefault, .unsupportedScheme:
            return finish(
                request,
                tabContext: tabContext,
                result: result,
                reason: coordinatorDecision.reason
            )

        case .openFailed:
            return finish(
                request,
                tabContext: tabContext,
                result: .openFailed,
                reason: "external-scheme-open-failed"
            )
        }
    }

    func securityContext(
        for request: SumiExternalSchemePermissionRequest,
        tabContext: SumiExternalSchemePermissionTabContext,
        bypassActivationGateForStoreLookup: Bool = false
    ) -> SumiPermissionSecurityContext {
        let topOrigin = topOrigin(for: tabContext)
        let hasUserGesture = bypassActivationGateForStoreLookup ? true : request.isUserActivated
        let permissionType = SumiPermissionType.externalScheme(request.normalizedScheme)
        let permissionRequest = SumiPermissionRequest(
            id: request.id,
            tabId: tabContext.tabId,
            pageId: tabContext.pageId,
            frameId: nil,
            requestingOrigin: request.requestingOrigin,
            topOrigin: topOrigin,
            displayDomain: tabContext.displayDomain ?? request.requestingOrigin.displayDomain,
            permissionTypes: [permissionType],
            hasUserGesture: hasUserGesture,
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
            hasUserGesture: hasUserGesture,
            isEphemeralProfile: tabContext.isEphemeralProfile,
            profilePartitionId: tabContext.profilePartitionId,
            transientPageId: tabContext.pageId,
            surface: .normalTab,
            navigationOrPageGeneration: tabContext.navigationOrPageGeneration,
            now: permissionRequest.requestedAt
        )
    }

    private func finish(
        _ request: SumiExternalSchemePermissionRequest,
        tabContext: SumiExternalSchemePermissionTabContext,
        result: SumiExternalSchemeAttemptResult,
        reason: String
    ) -> SumiExternalSchemePermissionResult {
        let record = sessionStore.record(
            SumiExternalSchemeAttemptRecord(
                id: request.id,
                tabId: tabContext.tabId,
                pageId: tabContext.pageId,
                requestingOrigin: request.requestingOrigin,
                topOrigin: topOrigin(for: tabContext),
                scheme: request.normalizedScheme,
                redactedTargetURLString: request.redactedTargetURLString,
                lastAttemptAt: now(),
                result: result,
                reason: reason,
                profilePartitionId: tabContext.profilePartitionId,
                isEphemeralProfile: tabContext.isEphemeralProfile,
                attemptCount: 1
            )
        )
        emitEvent(for: record)

        switch result {
        case .opened:
            return SumiExternalSchemePermissionResult(
                action: .opened(record)
            )
        case .blockedByDefault, .blockedByStoredDeny, .blockedPromptPresenterUnavailable:
            return SumiExternalSchemePermissionResult(
                action: .blocked(record)
            )
        case .unsupportedScheme:
            return SumiExternalSchemePermissionResult(
                action: .unsupported(record)
            )
        case .openFailed:
            return SumiExternalSchemePermissionResult(
                action: .openFailed(record)
            )
        }
    }

    private func topOrigin(for tabContext: SumiExternalSchemePermissionTabContext) -> SumiPermissionOrigin {
        SumiPermissionOrigin(url: tabContext.committedURL ?? tabContext.mainFrameURL ?? tabContext.visibleURL)
    }

    private func emitEvent(for record: SumiExternalSchemeAttemptRecord) {
        switch record.result {
        case .opened:
            emit(.opened(requestId: record.id, pageId: record.pageId, scheme: record.scheme))
        case .blockedByDefault:
            emit(.blockedByDefault(requestId: record.id, pageId: record.pageId, reason: record.reason))
        case .blockedByStoredDeny:
            emit(.blockedByStoredDeny(requestId: record.id, pageId: record.pageId, reason: record.reason))
        case .blockedPromptPresenterUnavailable:
            emit(.blockedPromptPresenterUnavailable(requestId: record.id, pageId: record.pageId, reason: record.reason))
        case .unsupportedScheme:
            emit(.unsupportedScheme(requestId: record.id, pageId: record.pageId, reason: record.reason))
        case .openFailed:
            emit(.openFailed(requestId: record.id, pageId: record.pageId, reason: record.reason))
        }
        if record.attemptCount > 1 {
            emit(.possibleAbuse(
                requestId: record.id,
                pageId: record.pageId,
                attemptCount: record.attemptCount
            ))
        }
    }

    private func emit(_ event: SumiExternalSchemePermissionEvent) {
        eventSink?(event)
    }
}
