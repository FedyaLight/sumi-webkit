import Foundation
import SumiDomain
import WebKit

enum SumiNotificationBridgeSource: String, Codable, Equatable, Sendable {
    case website
}

enum SumiNotificationPermissionEvent: Equatable, Sendable {
    case permissionRequested(source: SumiNotificationBridgeSource, requestId: String)
    case promptPresenterUnavailable(source: SumiNotificationBridgeSource, requestId: String)
    case blockedBySystem(source: SumiNotificationBridgeSource, requestId: String, reason: String)
    case blockedBySite(source: SumiNotificationBridgeSource, requestId: String, reason: String)
    case delivered(source: SumiNotificationBridgeSource, requestId: String, identifier: String)
    case failed(source: SumiNotificationBridgeSource, requestId: String, reason: String)
}

struct SumiNotificationPostResult: Equatable, Sendable {
    let delivered: Bool
    let permission: SumiWebNotificationPermissionState
    let reason: String
    let identifier: SumiNotificationIdentifier?

    static func blocked(
        permission: SumiWebNotificationPermissionState,
        reason: String
    ) -> SumiNotificationPostResult {
        SumiNotificationPostResult(
            delivered: false,
            permission: permission,
            reason: reason,
            identifier: nil
        )
    }
}

@MainActor
final class SumiNotificationPermissionBridge {
    typealias PageValidator = @MainActor () -> Bool
    typealias EventSink = @MainActor (SumiNotificationPermissionEvent) -> Void

    private let coordinator: any SumiPermissionCoordinating
    private let notificationService: any SumiNotificationServicing
    private let pendingStrategy: SumiNotificationPendingStrategy
    private let pendingPollIntervalNanoseconds: UInt64
    private let coordinatorTimeoutNanoseconds: UInt64
    private let now: @Sendable () -> Date
    private let eventSink: EventSink?
    private let indicatorEventStore: SumiPermissionIndicatorEventStore?

    init(
        coordinator: any SumiPermissionCoordinating,
        notificationService: any SumiNotificationServicing,
        pendingStrategy: SumiNotificationPendingStrategy = .waitForPromptUI,
        pendingPollIntervalNanoseconds: UInt64 = 25_000_000,
        coordinatorTimeoutNanoseconds: UInt64 = 500_000_000,
        now: @escaping @Sendable () -> Date = { Date() },
        eventSink: EventSink? = nil,
        indicatorEventStore: SumiPermissionIndicatorEventStore? = nil
    ) {
        self.coordinator = coordinator
        self.notificationService = notificationService
        self.pendingStrategy = pendingStrategy
        self.pendingPollIntervalNanoseconds = pendingPollIntervalNanoseconds
        self.coordinatorTimeoutNanoseconds = coordinatorTimeoutNanoseconds
        self.now = now
        self.eventSink = eventSink
        self.indicatorEventStore = indicatorEventStore
    }

    func currentWebsitePermissionState(
        request: SumiWebNotificationRequest,
        tabContext: SumiWebNotificationTabContext
    ) async -> SumiWebNotificationPermissionState {
        guard request.isMainFrame else {
            return .denied
        }
        let context = securityContext(for: request, tabContext: tabContext)
        let decision = await coordinator.queryPermissionState(context)
        return SumiWebNotificationDecisionMapper.permissionState(for: decision)
    }

    func requestWebsitePermission(
        request: SumiWebNotificationRequest,
        tabContext: SumiWebNotificationTabContext
    ) async -> SumiWebNotificationPermissionState {
        guard request.isMainFrame else {
            return .denied
        }
        emit(.permissionRequested(source: .website, requestId: request.id))
        let context = securityContext(for: request, tabContext: tabContext)
        let decision = await coordinatorDecision(for: context, source: .website)
        recordNotificationIndicatorEvent(for: decision, context: context)
        guard decision.outcome != .granted || tabContext.isCurrentPage?() != false else {
            await coordinator.cancel(
                requestId: context.request.id,
                reason: "website-notification-permission-stale-page"
            )
            return .default
        }
        return SumiWebNotificationDecisionMapper.permissionState(
            for: decision,
            promptRequiredState: .default,
            dismissedState: .default,
            cancelledState: .default
        )
    }

    func postWebsiteNotification(
        request: SumiWebNotificationRequest,
        tabContext: SumiWebNotificationTabContext,
        title: String,
        body: String,
        iconURL: URL?,
        imageURL: URL?,
        tag: String?,
        isSilent: Bool,
        webView: WKWebView?,
        pageValidator: PageValidator? = nil
    ) async -> SumiNotificationPostResult {
        guard request.isMainFrame else {
            return .blocked(permission: .denied, reason: "website-notification-subframe-denied")
        }
        guard webView != nil, pageValidator?() != false else {
            return .blocked(permission: .denied, reason: "website-notification-page-cancelled")
        }

        let context = securityContext(for: request, tabContext: tabContext)
        let decision = await coordinator.queryPermissionState(context)
        guard SumiWebNotificationDecisionMapper.canDeliver(decision) else {
            recordNotificationIndicatorEvent(for: decision, context: context)
            emitBlockedEvent(source: .website, requestId: request.id, decision: decision)
            return .blocked(
                permission: SumiWebNotificationDecisionMapper.permissionState(for: decision),
                reason: decision.reason
            )
        }
        guard webView != nil, pageValidator?() != false else {
            return .blocked(permission: .denied, reason: "website-notification-page-cancelled")
        }

        let identifier = SumiNotificationIdentifier.website(
            profilePartitionId: tabContext.profilePartitionId,
            tabId: tabContext.tabId,
            pageId: tabContext.pageId,
            requestId: request.id
        )
        let payload = SumiNotificationPayload(
            identifier: identifier,
            kind: .website,
            title: title,
            body: body,
            iconURL: sameOriginURL(iconURL, requestingOrigin: request.requestingOrigin),
            imageURL: sameOriginURL(imageURL, requestingOrigin: request.requestingOrigin),
            tag: tag,
            isSilent: isSilent,
            userInfo: notificationUserInfo(
                source: .website,
                request: request,
                tabContext: tabContext
            )
        )

        let result = await notificationService.post(payload)
        switch result {
        case .delivered(let deliveredIdentifier):
            emit(.delivered(
                source: .website,
                requestId: request.id,
                identifier: deliveredIdentifier.rawValue
            ))
            return SumiNotificationPostResult(
                delivered: true,
                permission: .granted,
                reason: "delivered",
                identifier: deliveredIdentifier
            )
        case .failed(_, let reason):
            emit(.failed(source: .website, requestId: request.id, reason: reason))
            return SumiNotificationPostResult(
                delivered: false,
                permission: .granted,
                reason: reason,
                identifier: identifier
            )
        }
    }

    func closeNotification(identifier: SumiNotificationIdentifier) async {
        await notificationService.close(identifier: identifier)
    }

    func securityContext(
        for request: SumiWebNotificationRequest,
        tabContext: SumiWebNotificationTabContext
    ) -> SumiPermissionSecurityContext {
        SumiPermissionSecurityContextBuilder.make(
            requestId: request.id,
            tabId: tabContext.tabId,
            pageId: tabContext.pageId,
            requestingOrigin: request.requestingOrigin,
            displayDomain: tabContext.displayDomain ?? request.requestingOrigin.displayDomain,
            permissionTypes: [.notifications],
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
        for context: SumiPermissionSecurityContext,
        source: SumiNotificationBridgeSource
    ) async -> SumiPermissionCoordinatorDecision {
        let outcome = await SumiPermissionPendingCoordinatorRace.run(
            coordinator: coordinator,
            context: context,
            shouldWaitForPromptUI: pendingStrategy.waitsForPromptUI,
            pendingReason: pendingStrategy.reason,
            timeoutReason: "notification-permission-coordinator-timeout",
            taskCancelledReason: "notification-permission-task-cancelled",
            noCoordinatorResultReason: "notification-permission-no-coordinator-result",
            pendingPollIntervalNanoseconds: pendingPollIntervalNanoseconds,
            coordinatorTimeoutNanoseconds: coordinatorTimeoutNanoseconds,
            temporaryPendingDecision: { context, reason in
                SumiWebNotificationDecisionMapper.temporaryPendingDecision(
                    for: context,
                    reason: reason
                )
            },
            failClosedDecision: { context, reason in
                SumiWebNotificationDecisionMapper.failClosedDecision(
                    for: context,
                    reason: reason
                )
            }
        )

        let requestId = context.request.id
        switch outcome {
        case .immediate(let decision):
            return decision
        case .coordinator(let decision):
            if decision.outcome == .promptRequired {
                emit(.promptPresenterUnavailable(source: source, requestId: requestId))
            }
            return decision
        case .pendingStrategy(let decision):
            emit(.promptPresenterUnavailable(source: source, requestId: requestId))
            return decision
        case .timeout(let decision):
            emit(.failed(source: source, requestId: requestId, reason: decision.reason))
            return decision
        }
    }

    private func emitBlockedEvent(
        source: SumiNotificationBridgeSource,
        requestId: String,
        decision: SumiPermissionCoordinatorDecision
    ) {
        switch decision.outcome {
        case .systemBlocked:
            emit(.blockedBySystem(source: source, requestId: requestId, reason: decision.reason))
        case .promptRequired:
            emit(.promptPresenterUnavailable(source: source, requestId: requestId))
        default:
            emit(.blockedBySite(source: source, requestId: requestId, reason: decision.reason))
        }
    }

    private func recordNotificationIndicatorEvent(
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
        if decision.outcome == .systemBlocked {
            category = .systemBlocked
            visualStyle = .systemWarning
            priority = .systemBlockedSensitive
        } else {
            category = .blockedEvent
            visualStyle = .blocked
            priority = .blockedNotification
        }

        indicatorEventStore?.record(
            SumiPermissionIndicatorEventRecord(
                id: "notification-\(context.request.id)-\(decision.outcome.rawValue)",
                tabId: context.request.tabId ?? context.request.pageBucketId,
                pageId: context.request.pageBucketId,
                displayDomain: context.request.displayDomain,
                permissionTypes: [.notifications],
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

    private func emit(_ event: SumiNotificationPermissionEvent) {
        eventSink?(event)
    }

    private func notificationUserInfo(
        source: SumiNotificationBridgeSource,
        request: SumiWebNotificationRequest,
        tabContext: SumiWebNotificationTabContext,
        extra: [String: String] = [:]
    ) -> [String: String] {
        let topOrigin = SumiPermissionOrigin(
            url: tabContext.committedURL ?? tabContext.mainFrameURL ?? tabContext.visibleURL
        )
        var userInfo = [
            "source": source.rawValue,
            "requestId": request.id,
            "requestingOrigin": request.requestingOrigin.identity,
            "topOrigin": topOrigin.identity,
            "topDisplayDomain": topOrigin.displayDomain,
            "tabId": tabContext.tabId,
            "pageId": tabContext.pageId,
            "profilePartitionId": tabContext.profilePartitionId,
        ]
        extra.forEach { userInfo[$0.key] = $0.value }
        return userInfo
    }

    private func sameOriginURL(
        _ url: URL?,
        requestingOrigin: SumiPermissionOrigin
    ) -> URL? {
        guard let url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              SumiPermissionOrigin(url: url).identity == requestingOrigin.identity
        else {
            return nil
        }
        return url
    }
}
