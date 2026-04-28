import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionPromptViewModelTests: XCTestCase {
    func testCameraShowsSensitiveActionMatrix() {
        let viewModel = makeViewModel(
            query: promptQuery(permissionTypes: [.camera])
        )

        XCTAssertEqual(
            viewModel.options.map(\.action),
            [.allowWhileVisiting, .allowThisTime, .dontAllow]
        )
        XCTAssertEqual(viewModel.title, "example.com wants to use your camera")
    }

    func testGroupedCameraMicrophoneUsesGroupedCopyAndActions() {
        let viewModel = makeViewModel(
            query: promptQuery(
                permissionTypes: [.camera, .microphone],
                presentationPermissionType: .cameraAndMicrophone
            )
        )

        XCTAssertEqual(viewModel.permissionType, .cameraAndMicrophone)
        XCTAssertEqual(viewModel.title, "example.com wants to use your camera and microphone")
        XCTAssertEqual(
            viewModel.options.map(\.action),
            [.allowWhileVisiting, .allowThisTime, .dontAllow]
        )
    }

    func testNotificationsDoNotOfferAllowThisTime() {
        let viewModel = makeViewModel(
            query: promptQuery(permissionTypes: [.notifications])
        )

        XCTAssertEqual(viewModel.options.map(\.action), [.allow, .dontAllow])
    }

    func testExternalSchemeShowsPersistentExternalActionOnlyForPersistentProfiles() {
        let persistent = makeViewModel(
            query: promptQuery(permissionTypes: [.externalScheme("zoommtg")])
        )
        let ephemeral = makeViewModel(
            query: promptQuery(
                permissionTypes: [.externalScheme("zoommtg")],
                availablePersistences: [.oneTime, .session],
                isEphemeralProfile: true
            )
        )

        XCTAssertEqual(
            persistent.options.map(\.action),
            [.openThisTime, .alwaysAllowExternal, .dontAllow]
        )
        XCTAssertEqual(ephemeral.options.map(\.action), [.openThisTime, .dontAllow])
    }

    func testAllowThisTimeRequestsSystemAuthorizationThenApprovesOnce() async {
        let coordinator = PromptFakeCoordinator()
        let systemService = FakeSumiSystemPermissionService(
            states: [.camera: .notDetermined],
            requestResults: [.camera: .authorized]
        )
        var finished = false
        let viewModel = makeViewModel(
            query: promptQuery(
                permissionTypes: [.camera],
                systemAuthorizationSnapshots: [
                    SumiSystemPermissionSnapshot(kind: .camera, state: .notDetermined),
                ]
            ),
            coordinator: coordinator,
            systemService: systemService,
            onFinished: { finished = true }
        )

        await viewModel.performAction(.allowThisTime)

        let requestCallCount = await systemService.requestAuthorizationCallCount(for: .camera)
        let settlementActions = await coordinator.settlementActions()
        XCTAssertEqual(requestCallCount, 1)
        XCTAssertEqual(settlementActions, [.approveOnce("query-a")])
        XCTAssertTrue(finished)
    }

    func testOpenThisTimeUsesCurrentAttemptSettlement() async {
        let coordinator = PromptFakeCoordinator()
        let viewModel = makeViewModel(
            query: promptQuery(permissionTypes: [.externalScheme("zoommtg")]),
            coordinator: coordinator
        )

        await viewModel.performAction(.openThisTime)

        let settlementActions = await coordinator.settlementActions()
        XCTAssertEqual(settlementActions, [.approveCurrentAttempt("query-a")])
    }

    func testDenyUsesSessionSettlementForEphemeralProfile() async {
        let coordinator = PromptFakeCoordinator()
        let viewModel = makeViewModel(
            query: promptQuery(
                permissionTypes: [.geolocation],
                availablePersistences: [.oneTime, .session],
                isEphemeralProfile: true
            ),
            coordinator: coordinator
        )

        await viewModel.performAction(.dontAllow)

        let settlementActions = await coordinator.settlementActions()
        XCTAssertEqual(settlementActions, [.denyForSession("query-a")])
    }

    func testSystemBlockedShowsSettingsAndDoesNotPersistSiteDecision() async {
        let coordinator = PromptFakeCoordinator()
        let systemService = FakeSumiSystemPermissionService(states: [.microphone: .denied])
        let viewModel = makeViewModel(
            query: promptQuery(
                permissionTypes: [.microphone],
                systemAuthorizationSnapshots: [
                    SumiSystemPermissionSnapshot(kind: .microphone, state: .denied),
                ]
            ),
            coordinator: coordinator,
            systemService: systemService
        )

        XCTAssertTrue(viewModel.isSystemBlocked)
        XCTAssertEqual(viewModel.options.map(\.action), [.openSystemSettings, .dismiss])

        await viewModel.performAction(.openSystemSettings)

        let openedSettingsKinds = await systemService.openedSettingsKinds()
        let settlementActions = await coordinator.settlementActions()
        XCTAssertEqual(openedSettingsKinds, [.microphone])
        XCTAssertEqual(
            settlementActions,
            [.cancel("query-a", "permission-prompt-open-system-settings")]
        )
    }

    private func makeViewModel(
        query: SumiPermissionAuthorizationQuery,
        coordinator: PromptFakeCoordinator = PromptFakeCoordinator(),
        systemService: FakeSumiSystemPermissionService = FakeSumiSystemPermissionService(
            states: [
                .camera: .authorized,
                .microphone: .authorized,
                .geolocation: .authorized,
                .notifications: .authorized,
                .screenCapture: .authorized,
            ]
        ),
        onFinished: @escaping @MainActor () -> Void = {}
    ) -> SumiPermissionPromptViewModel {
        SumiPermissionPromptViewModel(
            query: query,
            coordinator: coordinator,
            systemPermissionService: systemService,
            onFinished: onFinished
        )
    }
}

private actor PromptFakeCoordinator: SumiPermissionCoordinating {
    enum SettlementAction: Equatable {
        case approveCurrentAttempt(String)
        case approveOnce(String)
        case approveForSession(String)
        case approvePersistently(String)
        case denyForSession(String)
        case denyPersistently(String)
        case dismiss(String)
        case cancel(String, String)
    }

    private var actions: [SettlementAction] = []

    func requestPermission(_ context: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .promptRequired,
            state: .ask,
            persistence: nil,
            source: .runtime,
            reason: "fake",
            permissionTypes: context.request.permissionTypes
        )
    }

    func queryPermissionState(_ context: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        await requestPermission(context)
    }

    func activeQuery(forPageId pageId: String) -> SumiPermissionAuthorizationQuery? {
        nil
    }

    func stateSnapshot() -> SumiPermissionCoordinatorState {
        SumiPermissionCoordinatorState()
    }

    func events() -> AsyncStream<SumiPermissionCoordinatorEvent> {
        AsyncStream { continuation in continuation.finish() }
    }

    @discardableResult
    func approveCurrentAttempt(_ queryId: String) -> SumiPermissionCoordinatorDecision {
        actions.append(.approveCurrentAttempt(queryId))
        return decision(.granted, queryId: queryId)
    }

    @discardableResult
    func approveOnce(_ queryId: String) -> SumiPermissionCoordinatorDecision {
        actions.append(.approveOnce(queryId))
        return decision(.granted, queryId: queryId)
    }

    @discardableResult
    func approveForSession(_ queryId: String) -> SumiPermissionCoordinatorDecision {
        actions.append(.approveForSession(queryId))
        return decision(.granted, queryId: queryId)
    }

    @discardableResult
    func approvePersistently(_ queryId: String) -> SumiPermissionCoordinatorDecision {
        actions.append(.approvePersistently(queryId))
        return decision(.granted, queryId: queryId)
    }

    @discardableResult
    func denyForSession(_ queryId: String) -> SumiPermissionCoordinatorDecision {
        actions.append(.denyForSession(queryId))
        return decision(.denied, queryId: queryId)
    }

    @discardableResult
    func denyPersistently(_ queryId: String) -> SumiPermissionCoordinatorDecision {
        actions.append(.denyPersistently(queryId))
        return decision(.denied, queryId: queryId)
    }

    @discardableResult
    func dismiss(_ queryId: String) -> SumiPermissionCoordinatorDecision {
        actions.append(.dismiss(queryId))
        return decision(.dismissed, queryId: queryId)
    }

    @discardableResult
    func cancel(queryId: String, reason: String) -> SumiPermissionCoordinatorDecision {
        actions.append(.cancel(queryId, reason))
        return decision(.cancelled, queryId: queryId, reason: reason)
    }

    @discardableResult
    func cancel(requestId: String, reason: String) -> SumiPermissionCoordinatorDecision {
        decision(.cancelled, queryId: requestId, reason: reason)
    }

    @discardableResult
    func cancel(pageId: String, reason: String) -> SumiPermissionCoordinatorDecision {
        decision(.cancelled, queryId: pageId, reason: reason)
    }

    @discardableResult
    func cancelNavigation(pageId: String, reason: String) -> SumiPermissionCoordinatorDecision {
        cancel(pageId: pageId, reason: reason)
    }

    @discardableResult
    func cancelTab(tabId: String, reason: String) -> SumiPermissionCoordinatorDecision {
        decision(.cancelled, queryId: tabId, reason: reason)
    }

    func settlementActions() -> [SettlementAction] {
        actions
    }

    private func decision(
        _ outcome: SumiPermissionCoordinatorOutcome,
        queryId: String,
        reason: String? = nil
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: outcome,
            state: outcome == .granted ? .allow : .deny,
            persistence: nil,
            source: .user,
            reason: reason ?? outcome.rawValue,
            permissionTypes: [.camera],
            queryId: queryId
        )
    }
}

private func promptQuery(
    permissionTypes: [SumiPermissionType],
    presentationPermissionType: SumiPermissionType? = nil,
    availablePersistences: Set<SumiPermissionPersistence> = [.oneTime, .session, .persistent],
    systemAuthorizationSnapshots: [SumiSystemPermissionSnapshot] = [],
    isEphemeralProfile: Bool = false
) -> SumiPermissionAuthorizationQuery {
    SumiPermissionAuthorizationQuery(
        id: "query-a",
        pageId: "tab-a:1",
        profilePartitionId: "profile-a",
        displayDomain: "example.com",
        requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
        topOrigin: SumiPermissionOrigin(string: "https://example.com"),
        permissionTypes: permissionTypes,
        presentationPermissionType: presentationPermissionType,
        availablePersistences: availablePersistences,
        defaultPersistence: .oneTime,
        systemAuthorizationSnapshots: systemAuthorizationSnapshots,
        policySources: [.defaultSetting],
        policyReasons: [SumiPermissionPolicyReason.allowed],
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        isEphemeralProfile: isEphemeralProfile,
        hasUserGesture: true,
        shouldOfferSystemSettings: systemAuthorizationSnapshots.contains(where: \.shouldOpenSystemSettings),
        disablesPersistentAllow: isEphemeralProfile || !availablePersistences.contains(.persistent),
        requiresSystemAuthorizationPrompt: systemAuthorizationSnapshots.contains { $0.state == .notDetermined }
    )
}
