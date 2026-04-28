import WebKit
import XCTest
@testable import Sumi

@MainActor
final class SumiNotificationPermissionBridgeTests: XCTestCase {
    func testSystemAuthorizedAndCoordinatorGrantedPostsNotification() async {
        let service = FakeSumiNotificationService()
        let coordinator = FakeNotificationPermissionCoordinator(
            mode: .immediate(decision(.granted, systemState: .authorized))
        )
        let bridge = makeBridge(coordinator: coordinator, service: service)

        let result = await bridge.postUserscriptNotification(
            request: notificationRequest(),
            tabContext: tabContext(),
            scriptId: "script-a",
            title: "Title",
            body: "Body",
            iconURL: nil,
            imageURL: nil,
            tag: "tag",
            isSilent: false,
            webView: WKWebView()
        )

        XCTAssertTrue(result.delivered)
        XCTAssertEqual(result.permission, .granted)
        let postedCount = await service.postedCount()
        let lastPayload = await service.lastPayload()
        XCTAssertEqual(postedCount, 1)
        XCTAssertEqual(lastPayload?.tag, "tag")
    }

    func testSystemBlockedDoesNotPostNotification() async {
        let service = FakeSumiNotificationService()
        let coordinator = FakeNotificationPermissionCoordinator(
            mode: .immediate(decision(.systemBlocked, systemState: .denied))
        )
        let bridge = makeBridge(coordinator: coordinator, service: service)

        let result = await bridge.postUserscriptNotification(
            request: notificationRequest(),
            tabContext: tabContext(),
            scriptId: "script-a",
            title: "Title",
            body: "Body",
            iconURL: nil,
            imageURL: nil,
            tag: nil,
            isSilent: false,
            webView: WKWebView()
        )

        XCTAssertFalse(result.delivered)
        XCTAssertEqual(result.permission, .denied)
        let postedCount = await service.postedCount()
        XCTAssertEqual(postedCount, 0)
    }

    func testPromptRequiredUsesTemporaryFailClosedStrategy() async {
        let service = FakeSumiNotificationService()
        let coordinator = FakeNotificationPermissionCoordinator(mode: .pending)
        let bridge = makeBridge(
            coordinator: coordinator,
            service: service,
            pendingPollIntervalNanoseconds: 1_000_000,
            coordinatorTimeoutNanoseconds: 50_000_000
        )

        let result = await bridge.postUserscriptNotification(
            request: notificationRequest(),
            tabContext: tabContext(),
            scriptId: "script-a",
            title: "Title",
            body: "Body",
            iconURL: nil,
            imageURL: nil,
            tag: nil,
            isSilent: false,
            webView: WKWebView()
        )

        XCTAssertFalse(result.delivered)
        XCTAssertEqual(result.permission, .denied)
        let postedCount = await service.postedCount()
        let cancelledReasons = await coordinator.cancelledReasons()
        XCTAssertEqual(postedCount, 0)
        XCTAssertEqual(cancelledReasons, ["notification-prompt-ui-unavailable-deny"])
    }

    func testWebsitePermissionStateMapsPromptToDefault() async {
        let bridge = makeBridge(
            coordinator: FakeNotificationPermissionCoordinator(
                mode: .query(
                    SumiPermissionCoordinatorDecision(
                        outcome: .promptRequired,
                        state: .ask,
                        persistence: nil,
                        source: .runtime,
                        reason: "no-site-decision",
                        permissionTypes: [.notifications],
                        systemAuthorizationSnapshot: SumiSystemPermissionSnapshot(kind: .notifications, state: .authorized)
                    )
                )
            ),
            service: FakeSumiNotificationService()
        )

        let state = await bridge.currentWebsitePermissionState(
            request: notificationRequest(),
            tabContext: tabContext()
        )

        XCTAssertEqual(state, .default)
    }

    func testWebsitePermissionRequestMapsPromptToDeniedWhilePromptUIIsAbsent() async {
        let bridge = makeBridge(
            coordinator: FakeNotificationPermissionCoordinator(mode: .pending),
            service: FakeSumiNotificationService(),
            pendingPollIntervalNanoseconds: 1_000_000,
            coordinatorTimeoutNanoseconds: 50_000_000
        )

        let state = await bridge.requestWebsitePermission(
            request: notificationRequest(),
            tabContext: tabContext()
        )

        XCTAssertEqual(state, .denied)
    }

    func testNotificationPayloadSanitizesTextAndIdentifiersAreDeterministic() {
        let first = SumiNotificationIdentifier.userscript(
            profilePartitionId: "Profile A",
            tabId: "Tab A",
            scriptId: "Script A",
            requestId: "Request A"
        )
        let second = SumiNotificationIdentifier.userscript(
            profilePartitionId: "Profile A",
            tabId: "Tab A",
            scriptId: "Script A",
            requestId: "Request A"
        )
        let payload = SumiNotificationPayload(
            identifier: first,
            kind: .userscript,
            title: "\u{0}  Hello  ",
            body: "Body\u{1}",
            isSilent: true
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(payload.title, "Hello")
        XCTAssertEqual(payload.body, "Body")
        XCTAssertTrue(payload.isSilent)
    }

    func testFakeNotificationServiceCanSimulateDeliveryFailure() async {
        let service = FakeSumiNotificationService()
        await service.setNextFailureReason("delivery-failed")
        let identifier = SumiNotificationIdentifier(rawValue: "id")
        let result = await service.post(
            SumiNotificationPayload(
                identifier: identifier,
                kind: .website,
                title: "Title",
                body: "Body"
            )
        )

        XCTAssertEqual(result, .failed(identifier: identifier, reason: "delivery-failed"))
    }

    func testSourceLevelNotificationAuthorizationIsolation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let gmBridge = try String(
            contentsOf: root.appendingPathComponent("Sumi/Managers/SumiScripts/UserScriptGMBridge.swift"),
            encoding: .utf8
        )
        let systemService = try String(
            contentsOf: root.appendingPathComponent("Sumi/Permissions/SumiSystemPermissionService.swift"),
            encoding: .utf8
        )
        let notificationBridge = try String(
            contentsOf: root.appendingPathComponent("Sumi/Permissions/SumiNotificationPermissionBridge.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(gmBridge.contains("requestAuthorization(options:"))
        XCTAssertFalse(gmBridge.contains("UNNotificationRequest("))
        XCTAssertTrue(systemService.contains("requestAuthorization(options:"))
        XCTAssertTrue(notificationBridge.contains("SumiPermissionCoordinating"))
        XCTAssertFalse(notificationBridge.contains("setDecision("))
    }

    func testDocumentationListsDDGNotificationReferenceFiles() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let handoff = try String(
            contentsOf: root.appendingPathComponent("docs/permissions/IMPLEMENTATION_HANDOFF.md"),
            encoding: .utf8
        )
        let licenseNotes = try String(
            contentsOf: root.appendingPathComponent("docs/permissions/LICENSE_NOTES.md"),
            encoding: .utf8
        )

        XCTAssertTrue(handoff.contains("WebNotificationsHandler.swift"))
        XCTAssertTrue(handoff.contains("WebNotificationsTabExtension.swift"))
        XCTAssertTrue(licenseNotes.contains("No DuckDuckGo implementation source was copied"))
    }

    private func makeBridge(
        coordinator: any SumiPermissionCoordinating,
        service: any SumiNotificationServicing,
        pendingPollIntervalNanoseconds: UInt64 = 25_000_000,
        coordinatorTimeoutNanoseconds: UInt64 = 500_000_000
    ) -> SumiNotificationPermissionBridge {
        SumiNotificationPermissionBridge(
            coordinator: coordinator,
            notificationService: service,
            pendingPollIntervalNanoseconds: pendingPollIntervalNanoseconds,
            coordinatorTimeoutNanoseconds: coordinatorTimeoutNanoseconds
        )
    }

    private func notificationRequest(
        id: String = "request-a",
        isMainFrame: Bool = true
    ) -> SumiWebNotificationRequest {
        SumiWebNotificationRequest(
            id: id,
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            frameURL: URL(string: "https://example.com/page"),
            isMainFrame: isMainFrame
        )
    }

    private func tabContext() -> SumiWebNotificationTabContext {
        SumiWebNotificationTabContext(
            tabId: "tab-a",
            pageId: "tab-a:1",
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            committedURL: URL(string: "https://example.com/page"),
            visibleURL: URL(string: "https://example.com/page"),
            mainFrameURL: URL(string: "https://example.com/page"),
            isActiveTab: true,
            isVisibleTab: true,
            navigationOrPageGeneration: "1"
        )
    }

    private func decision(
        _ outcome: SumiPermissionCoordinatorOutcome,
        systemState: SumiSystemPermissionAuthorizationState
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: outcome,
            state: outcome == .granted ? .allow : .deny,
            persistence: outcome == .granted ? .persistent : .session,
            source: outcome == .systemBlocked ? .system : .user,
            reason: outcome.rawValue,
            permissionTypes: [.notifications],
            systemAuthorizationSnapshot: SumiSystemPermissionSnapshot(
                kind: .notifications,
                state: systemState
            )
        )
    }
}

private actor FakeNotificationPermissionCoordinator: SumiPermissionCoordinating {
    enum Mode {
        case immediate(SumiPermissionCoordinatorDecision)
        case query(SumiPermissionCoordinatorDecision)
        case pending
    }

    private let mode: Mode
    private var contexts: [SumiPermissionSecurityContext] = []
    private var activeQueries: [String: SumiPermissionAuthorizationQuery] = [:]
    private var continuations: [String: CheckedContinuation<SumiPermissionCoordinatorDecision, Never>] = [:]
    private var cancelReasons: [String] = []

    init(mode: Mode) {
        self.mode = mode
    }

    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        switch mode {
        case .immediate(let decision),
             .query(let decision):
            return decision
        case .pending:
            let query = authorizationQuery(for: context)
            activeQueries[query.pageId] = query
            return await withCheckedContinuation { continuation in
                continuations[context.request.id] = continuation
            }
        }
    }

    func queryPermissionState(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        switch mode {
        case .immediate(let decision),
             .query(let decision):
            return decision
        case .pending:
            return SumiPermissionCoordinatorDecision(
                outcome: .promptRequired,
                state: .ask,
                persistence: nil,
                source: .runtime,
                reason: "fake-query-prompt-required",
                permissionTypes: [.notifications],
                keys: [context.request.key(for: .notifications)],
                systemAuthorizationSnapshot: SumiSystemPermissionSnapshot(kind: .notifications, state: .authorized)
            )
        }
    }

    func activeQuery(forPageId pageId: String) -> SumiPermissionAuthorizationQuery? {
        activeQueries[pageId]
    }

    func stateSnapshot() -> SumiPermissionCoordinatorState {
        SumiPermissionCoordinatorState(activeQueriesByPageId: activeQueries)
    }

    func events() -> AsyncStream<SumiPermissionCoordinatorEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    @discardableResult
    func cancel(
        requestId: String,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        cancelReasons.append(reason)
        let context = contexts.first { $0.request.id == requestId }
        let decision = SumiWebNotificationDecisionMapper.failClosedDecision(
            for: context,
            reason: reason
        )
        if let pageId = context?.request.pageBucketId {
            activeQueries[pageId] = nil
        }
        continuations.removeValue(forKey: requestId)?.resume(returning: decision)
        return decision
    }

    @discardableResult
    func cancel(
        pageId: String,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        cancelReasons.append(reason)
        activeQueries[pageId] = nil
        return SumiWebNotificationDecisionMapper.failClosedDecision(
            for: nil,
            reason: reason
        )
    }

    @discardableResult
    func cancelNavigation(
        pageId: String,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        cancel(pageId: pageId, reason: reason)
    }

    @discardableResult
    func cancelTab(
        tabId: String,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        cancelReasons.append(reason)
        return SumiWebNotificationDecisionMapper.failClosedDecision(
            for: nil,
            reason: reason
        )
    }

    func cancelledReasons() -> [String] {
        cancelReasons
    }

    private func authorizationQuery(
        for context: SumiPermissionSecurityContext
    ) -> SumiPermissionAuthorizationQuery {
        SumiPermissionAuthorizationQuery(
            id: "query-\(context.request.id)",
            pageId: context.request.pageBucketId,
            profilePartitionId: context.profilePartitionId,
            displayDomain: context.request.displayDomain,
            requestingOrigin: context.requestingOrigin,
            topOrigin: context.topOrigin,
            permissionTypes: [.notifications],
            presentationPermissionType: nil,
            availablePersistences: [.oneTime, .session, .persistent],
            defaultPersistence: .oneTime,
            systemAuthorizationSnapshots: [
                SumiSystemPermissionSnapshot(kind: .notifications, state: .authorized)
            ],
            policySources: [.defaultSetting],
            policyReasons: [SumiPermissionPolicyReason.allowed],
            createdAt: context.now,
            isEphemeralProfile: context.isEphemeralProfile,
            hasUserGesture: context.hasUserGesture,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context.isEphemeralProfile,
            requiresSystemAuthorizationPrompt: false
        )
    }
}
