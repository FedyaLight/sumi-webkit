import Foundation
import WebKit

enum SumiNotificationBridgeSource: String, Codable, Equatable, Sendable {
    case website
    case userscript
}

enum SumiNotificationPermissionEvent: Equatable, Sendable {
    case permissionRequested(source: SumiNotificationBridgeSource, requestId: String)
    case promptNeededNoUI(source: SumiNotificationBridgeSource, requestId: String)
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
    private enum CoordinatorRaceResult: Sendable {
        case coordinator(SumiPermissionCoordinatorDecision)
        case pendingStrategy(SumiPermissionCoordinatorDecision)
        case timeout(SumiPermissionCoordinatorDecision)
    }

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

    func postUserscriptNotification(
        request: SumiWebNotificationRequest,
        tabContext: SumiWebNotificationTabContext,
        scriptId: String,
        title: String,
        body: String,
        iconURL: URL?,
        imageURL: URL?,
        tag: String?,
        isSilent: Bool,
        webView: WKWebView?,
        pageValidator: PageValidator? = nil
    ) async -> SumiNotificationPostResult {
        guard webView != nil, pageValidator?() != false else {
            return .blocked(permission: .denied, reason: "userscript-notification-page-cancelled")
        }

        let context = securityContext(for: request, tabContext: tabContext)
        let decision = await coordinatorDecision(for: context, source: .userscript)
        guard SumiWebNotificationDecisionMapper.canDeliver(decision) else {
            recordNotificationIndicatorEvent(for: decision, context: context)
            emitBlockedEvent(source: .userscript, requestId: request.id, decision: decision)
            return .blocked(
                permission: SumiWebNotificationDecisionMapper.permissionState(
                    for: decision,
                    promptRequiredState: .default,
                    dismissedState: .default,
                    cancelledState: .default
                ),
                reason: decision.reason
            )
        }
        guard webView != nil, pageValidator?() != false else {
            return .blocked(permission: .denied, reason: "userscript-notification-page-cancelled")
        }

        let identifier = SumiNotificationIdentifier.userscript(
            profilePartitionId: tabContext.profilePartitionId,
            tabId: tabContext.tabId,
            scriptId: scriptId,
            requestId: request.id
        )
        let payload = SumiNotificationPayload(
            identifier: identifier,
            kind: .userscript,
            title: title,
            body: body,
            iconURL: sameOriginURL(iconURL, requestingOrigin: request.requestingOrigin),
            imageURL: sameOriginURL(imageURL, requestingOrigin: request.requestingOrigin),
            tag: tag,
            isSilent: isSilent,
            userInfo: notificationUserInfo(
                source: .userscript,
                request: request,
                tabContext: tabContext,
                extra: ["scriptId": scriptId]
            )
        )

        let result = await notificationService.post(payload)
        switch result {
        case .delivered(let deliveredIdentifier):
            emit(.delivered(
                source: .userscript,
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
            emit(.failed(source: .userscript, requestId: request.id, reason: reason))
            return SumiNotificationPostResult(
                delivered: false,
                permission: .granted,
                reason: reason,
                identifier: identifier
            )
        }
    }

    func securityContext(
        for request: SumiWebNotificationRequest,
        tabContext: SumiWebNotificationTabContext
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
            displayDomain: tabContext.displayDomain ?? request.requestingOrigin.displayDomain,
            permissionTypes: [.notifications],
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
        for context: SumiPermissionSecurityContext,
        source: SumiNotificationBridgeSource
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
                            SumiWebNotificationDecisionMapper.failClosedDecision(
                                for: context,
                                reason: "notification-permission-task-cancelled"
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
                            SumiWebNotificationDecisionMapper.temporaryPendingDecision(
                                for: context,
                                reason: pendingStrategy.reason
                            )
                        )
                    }
                }

                await coordinator.cancel(
                    requestId: requestId,
                    reason: "notification-permission-coordinator-timeout"
                )
                return .timeout(
                    SumiWebNotificationDecisionMapper.failClosedDecision(
                        for: context,
                        reason: "notification-permission-coordinator-timeout"
                    )
                )
            }

            guard let result = await group.next() else {
                return SumiWebNotificationDecisionMapper.failClosedDecision(
                    for: context,
                    reason: "notification-permission-no-coordinator-result"
                )
            }
            group.cancelAll()

            switch result {
            case .coordinator(let decision):
                if decision.outcome == .promptRequired {
                    emit(.promptNeededNoUI(source: source, requestId: requestId))
                }
                return decision
            case .pendingStrategy(let decision):
                emit(.promptNeededNoUI(source: source, requestId: requestId))
                return decision
            case .timeout(let decision):
                emit(.failed(source: source, requestId: requestId, reason: decision.reason))
                return decision
            }
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
            emit(.promptNeededNoUI(source: source, requestId: requestId))
        default:
            emit(.blockedBySite(source: source, requestId: requestId, reason: decision.reason))
        }
    }

    private func recordNotificationIndicatorEvent(
        for decision: SumiPermissionCoordinatorDecision,
        context: SumiPermissionSecurityContext
    ) {
        guard decision.outcome != .granted,
              decision.outcome != .ignored
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
        var userInfo = [
            "source": source.rawValue,
            "requestId": request.id,
            "requestingOrigin": request.requestingOrigin.identity,
            "topURL": (tabContext.committedURL ?? tabContext.mainFrameURL ?? tabContext.visibleURL)?.absoluteString ?? "",
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
