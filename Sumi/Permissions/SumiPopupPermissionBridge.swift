import Common
import Foundation
import WebKit

enum SumiPopupPermissionEvent: Equatable, Sendable {
    case attempted(requestId: String, pageId: String, classification: SumiPopupClassification)
    case allowedByUserActivation(requestId: String, pageId: String)
    case allowedByStoredOrSessionPolicy(requestId: String, pageId: String, reason: String)
    case allowedBrowserOwned(requestId: String, pageId: String)
    case blockedByDefault(requestId: String, pageId: String, reason: String)
    case blockedByStoredDeny(requestId: String, pageId: String, reason: String)
    case openedLater(requestId: String, pageId: String, targetURL: URL)
    case possibleAbuse(requestId: String, pageId: String, attemptCount: Int)
}

@MainActor
final class SumiPopupPermissionBridge {
    typealias EventSink = @MainActor (SumiPopupPermissionEvent) -> Void

    private let coordinator: any SumiPermissionCoordinating
    let blockedPopupStore: SumiBlockedPopupStore
    private let pendingStrategy: SumiPopupPendingStrategy
    private let now: @Sendable () -> Date
    private let eventSink: EventSink?

    init(
        coordinator: any SumiPermissionCoordinating,
        blockedPopupStore: SumiBlockedPopupStore? = nil,
        pendingStrategy: SumiPopupPendingStrategy = .backgroundPromptUnavailableBlock,
        now: @escaping @Sendable () -> Date = { Date() },
        eventSink: EventSink? = nil
    ) {
        self.coordinator = coordinator
        self.blockedPopupStore = blockedPopupStore ?? SumiBlockedPopupStore()
        self.pendingStrategy = pendingStrategy
        self.now = now
        self.eventSink = eventSink
    }

    func evaluate(
        _ request: SumiPopupPermissionRequest,
        tabContext: SumiPopupPermissionTabContext
    ) async -> SumiPopupPermissionResult {
        emit(.attempted(
            requestId: request.id,
            pageId: tabContext.pageId,
            classification: request.classification
        ))

        if request.classification == .internalOrBrowserOwned,
           request.isExtensionOwnedPopup,
           !request.involvesSumiInternalScheme {
            emit(.allowedBrowserOwned(requestId: request.id, pageId: tabContext.pageId))
            return SumiPopupPermissionResult(
                action: .allow,
                coordinatorDecision: nil,
                reason: "popup-browser-owned-allowed"
            )
        }
        if request.classification == .internalOrBrowserOwned {
            return block(
                request,
                tabContext: tabContext,
                decision: nil,
                reason: "popup-browser-owned-blocked",
                blockedReason: .blockedByPolicy
            )
        }

        guard request.targetURL?.navigationalScheme != .javascript else {
            return block(
                request,
                tabContext: tabContext,
                decision: nil,
                reason: "popup-javascript-url-blocked",
                blockedReason: .blockedByPolicy
            )
        }

        guard request.requestingOrigin.isWebOrigin,
              topOrigin(for: tabContext).isWebOrigin
        else {
            return block(
                request,
                tabContext: tabContext,
                decision: nil,
                reason: "popup-origin-not-keyable",
                blockedReason: .blockedByInvalidOrigin
            )
        }

        let context = securityContext(
            for: request,
            tabContext: tabContext,
            bypassActivationGateForStoreLookup: true
        )
        let coordinatorDecision = await coordinator.queryPermissionState(context)

        switch coordinatorDecision.outcome {
        case .granted:
            emit(.allowedByStoredOrSessionPolicy(
                requestId: request.id,
                pageId: tabContext.pageId,
                reason: coordinatorDecision.reason
            ))
            return SumiPopupPermissionResult(
                action: .allow,
                coordinatorDecision: coordinatorDecision,
                reason: coordinatorDecision.reason
            )

        case .denied:
            return block(
                request,
                tabContext: tabContext,
                decision: coordinatorDecision,
                reason: coordinatorDecision.reason,
                blockedReason: SumiPopupDecisionMapper.blockedReason(for: coordinatorDecision)
            )

        case .promptRequired:
            if request.isUserActivated {
                let defaultDecision = SumiPopupDecisionMapper.defaultAllowDecision(
                    for: context.replacingUserGesture(request.isUserActivated),
                    reason: "popup-user-activation-default-allow"
                )
                emit(.allowedByUserActivation(requestId: request.id, pageId: tabContext.pageId))
                return SumiPopupPermissionResult(
                    action: .allow,
                    coordinatorDecision: defaultDecision,
                    reason: defaultDecision.reason
                )
            }
            let decision = SumiPopupDecisionMapper.defaultBlockDecision(
                for: context.replacingUserGesture(false),
                reason: pendingStrategy.reason,
                source: .defaultSetting
            )
            return block(
                request,
                tabContext: tabContext,
                decision: decision,
                reason: decision.reason,
                blockedReason: .blockedByBackgroundPromptUnavailable
            )

        case .requiresUserActivation:
            return block(
                request,
                tabContext: tabContext,
                decision: coordinatorDecision,
                reason: "popup-background-default-block",
                blockedReason: .blockedByDefault
            )

        case .systemBlocked, .unsupported, .cancelled, .dismissed, .suppressed, .ignored, .expired:
            return block(
                request,
                tabContext: tabContext,
                decision: coordinatorDecision,
                reason: coordinatorDecision.reason,
                blockedReason: SumiPopupDecisionMapper.blockedReason(for: coordinatorDecision)
            )
        }
    }

    func evaluateSynchronouslyForWebKitFallback(
        _ request: SumiPopupPermissionRequest,
        tabContext: SumiPopupPermissionTabContext
    ) -> SumiPopupPermissionResult {
        emit(.attempted(
            requestId: request.id,
            pageId: tabContext.pageId,
            classification: request.classification
        ))

        if request.classification == .internalOrBrowserOwned,
           request.isExtensionOwnedPopup,
           !request.involvesSumiInternalScheme {
            emit(.allowedBrowserOwned(requestId: request.id, pageId: tabContext.pageId))
            return SumiPopupPermissionResult(
                action: .allow,
                coordinatorDecision: nil,
                reason: "popup-browser-owned-allowed"
            )
        }
        if request.classification == .internalOrBrowserOwned {
            return block(
                request,
                tabContext: tabContext,
                decision: nil,
                reason: "popup-browser-owned-blocked",
                blockedReason: .blockedByPolicy
            )
        }

        guard request.targetURL?.navigationalScheme != .javascript else {
            return block(
                request,
                tabContext: tabContext,
                decision: nil,
                reason: "popup-javascript-url-blocked",
                blockedReason: .blockedByPolicy
            )
        }
        guard request.requestingOrigin.isWebOrigin,
              topOrigin(for: tabContext).isWebOrigin
        else {
            return block(
                request,
                tabContext: tabContext,
                decision: nil,
                reason: "popup-origin-not-keyable",
                blockedReason: .blockedByInvalidOrigin
            )
        }

        if request.isUserActivated {
            emit(.allowedByUserActivation(requestId: request.id, pageId: tabContext.pageId))
            return SumiPopupPermissionResult(
                action: .allow,
                coordinatorDecision: nil,
                reason: "popup-user-activation-default-allow-sync-fallback"
            )
        }

        return block(
            request,
            tabContext: tabContext,
            decision: nil,
            reason: pendingStrategy.reason,
            blockedReason: .blockedByBackgroundPromptUnavailable
        )
    }

    func securityContext(
        for request: SumiPopupPermissionRequest,
        tabContext: SumiPopupPermissionTabContext,
        bypassActivationGateForStoreLookup: Bool = false
    ) -> SumiPermissionSecurityContext {
        let topOrigin = topOrigin(for: tabContext)
        let hasUserGesture = bypassActivationGateForStoreLookup ? true : request.isUserActivated
        let permissionRequest = SumiPermissionRequest(
            id: request.id,
            tabId: tabContext.tabId,
            pageId: tabContext.pageId,
            frameId: nil,
            requestingOrigin: request.requestingOrigin,
            topOrigin: topOrigin,
            displayDomain: tabContext.displayDomain ?? request.requestingOrigin.displayDomain,
            permissionTypes: [.popups],
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

    func blockedPopups(forPageId pageId: String) -> [SumiBlockedPopupRecord] {
        blockedPopupStore.records(forPageId: pageId)
    }

    @discardableResult
    func openBlockedPopup(
        id: String,
        pageId: String,
        opener: (URL) -> Void
    ) -> Bool {
        guard let record = blockedPopupStore.reopenableRecord(id: id, pageId: pageId),
              let targetURL = record.targetURL
        else {
            return false
        }
        opener(targetURL)
        emit(.openedLater(requestId: record.id, pageId: record.pageId, targetURL: targetURL))
        return true
    }

    private func block(
        _ request: SumiPopupPermissionRequest,
        tabContext: SumiPopupPermissionTabContext,
        decision: SumiPermissionCoordinatorDecision?,
        reason: String,
        blockedReason: SumiBlockedPopupRecord.Reason
    ) -> SumiPopupPermissionResult {
        let record = blockedPopupStore.record(
            SumiBlockedPopupRecord(
                id: request.id,
                tabId: tabContext.tabId,
                pageId: tabContext.pageId,
                requestingOrigin: request.requestingOrigin,
                topOrigin: topOrigin(for: tabContext),
                targetURL: request.targetURL,
                sourceURL: request.sourceURL ?? tabContext.committedURL,
                createdAt: now(),
                lastBlockedAt: now(),
                userActivation: request.userActivation,
                reason: blockedReason,
                canOpenLater: request.canOpenLater,
                navigationActionMetadata: request.navigationActionMetadata,
                profilePartitionId: tabContext.profilePartitionId,
                isEphemeralProfile: tabContext.isEphemeralProfile,
                attemptCount: 1
            )
        )

        switch blockedReason {
        case .blockedByStoredDeny:
            emit(.blockedByStoredDeny(
                requestId: request.id,
                pageId: tabContext.pageId,
                reason: reason
            ))
        default:
            emit(.blockedByDefault(
                requestId: request.id,
                pageId: tabContext.pageId,
                reason: reason
            ))
        }
        if record.attemptCount > 1 {
            emit(.possibleAbuse(
                requestId: request.id,
                pageId: tabContext.pageId,
                attemptCount: record.attemptCount
            ))
        }
        return SumiPopupPermissionResult(
            action: .block(record),
            coordinatorDecision: decision,
            reason: reason
        )
    }

    private func topOrigin(for tabContext: SumiPopupPermissionTabContext) -> SumiPermissionOrigin {
        SumiPermissionOrigin(url: tabContext.committedURL ?? tabContext.mainFrameURL ?? tabContext.visibleURL)
    }

    private func emit(_ event: SumiPopupPermissionEvent) {
        eventSink?(event)
    }
}

private extension SumiPermissionSecurityContext {
    func replacingUserGesture(_ hasUserGesture: Bool) -> SumiPermissionSecurityContext {
        let permissionRequest = SumiPermissionRequest(
            id: request.id,
            tabId: request.tabId,
            pageId: request.pageId,
            frameId: request.frameId,
            requestingOrigin: request.requestingOrigin,
            topOrigin: request.topOrigin,
            displayDomain: request.displayDomain,
            permissionTypes: request.permissionTypes,
            hasUserGesture: hasUserGesture,
            requestedAt: request.requestedAt,
            isEphemeralProfile: request.isEphemeralProfile,
            profilePartitionId: request.profilePartitionId
        )
        return SumiPermissionSecurityContext(
            request: permissionRequest,
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            committedURL: committedURL,
            visibleURL: visibleURL,
            mainFrameURL: mainFrameURL,
            isMainFrame: isMainFrame,
            isActiveTab: isActiveTab,
            isVisibleTab: isVisibleTab,
            hasUserGesture: hasUserGesture,
            isEphemeralProfile: isEphemeralProfile,
            profilePartitionId: profilePartitionId,
            transientPageId: transientPageId,
            surface: surface,
            navigationOrPageGeneration: navigationOrPageGeneration,
            now: now
        )
    }
}
