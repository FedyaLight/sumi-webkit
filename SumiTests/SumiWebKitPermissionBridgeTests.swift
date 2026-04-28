import WebKit
import XCTest

@testable import Sumi

@available(macOS 13.0, *)
@MainActor
final class SumiWebKitPermissionBridgeTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testMediaTypeMapping() {
        XCTAssertEqual(
            SumiWebKitMediaCaptureDecisionMapper.permissionTypes(for: .camera),
            [.camera]
        )
        XCTAssertEqual(
            SumiWebKitMediaCaptureDecisionMapper.permissionTypes(for: .microphone),
            [.microphone]
        )
        XCTAssertEqual(
            SumiWebKitMediaCaptureDecisionMapper.permissionTypes(for: .cameraAndMicrophone),
            [.camera, .microphone]
        )

        let unknown = WKMediaCaptureType(rawValue: 999)!
        XCTAssertEqual(
            SumiWebKitMediaCaptureDecisionMapper.permissionTypes(for: unknown),
            []
        )
    }

    func testSecurityContextConstructionUsesTrustedBrowserData() {
        let coordinator = FakePermissionCoordinator(mode: .immediate(decision(.denied, reason: "test-deny")))
        let bridge = makeBridge(coordinator: coordinator)
        let request = mediaRequest(
            permissionTypes: [.camera],
            requestingOrigin: SumiPermissionOrigin(string: "https://camera.example")
        )
        let context = bridge.securityContext(
            for: request,
            tabContext: tabContext(
                profilePartitionId: "Profile-A",
                isEphemeralProfile: true,
                committedURL: URL(string: "https://top.example/path")!,
                visibleURL: URL(string: "https://visible.example/path")!
            )
        )

        XCTAssertEqual(context.surface, .normalTab)
        XCTAssertEqual(context.requestingOrigin.identity, "https://camera.example")
        XCTAssertEqual(context.topOrigin.identity, "https://top.example")
        XCTAssertEqual(context.profilePartitionId, "profile-a")
        XCTAssertTrue(context.isEphemeralProfile)
        XCTAssertEqual(context.committedURL?.host(), "top.example")
        XCTAssertEqual(context.visibleURL?.host(), "visible.example")
        XCTAssertEqual(context.transientPageId, "tab-a:1")
        XCTAssertEqual(context.request.displayDomain, "camera.example")
    }

    func testMissingTrustedTopOriginDeniesThroughCoordinator() async {
        let store = BridgePermissionStore()
        let coordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: FakeSumiSystemPermissionService(states: [.camera: .authorized])
            ),
            persistentStore: store,
            now: { self.fixedDate }
        )
        let bridge = makeBridge(coordinator: coordinator)

        let decisions = await resolve(
            bridge: bridge,
            request: mediaRequest(permissionTypes: [.camera]),
            tabContext: tabContext(
                committedURL: nil,
                visibleURL: nil,
                mainFrameURL: nil
            )
        )

        XCTAssertEqual(decisions, [.deny])
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
    }

    func testCoordinatorDecisionMapping() async {
        let outcomes: [(SumiPermissionCoordinatorOutcome, WKPermissionDecision)] = [
            (.granted, .grant),
            (.denied, .deny),
            (.systemBlocked, .deny),
            (.unsupported, .deny),
            (.requiresUserActivation, .deny),
            (.cancelled, .deny),
            (.dismissed, .deny),
            (.ignored, .deny),
            (.expired, .deny),
            (.promptRequired, .deny),
        ]

        for (outcome, expectedWebKitDecision) in outcomes {
            let coordinator = FakePermissionCoordinator(
                mode: .immediate(decision(outcome, reason: "decision-\(outcome.rawValue)"))
            )
            let bridge = makeBridge(coordinator: coordinator)
            let decisions = await resolve(
                bridge: bridge,
                request: mediaRequest(permissionTypes: [.camera])
            )

            XCTAssertEqual(decisions, [expectedWebKitDecision], "outcome \(outcome)")
        }
    }

    func testSystemBlockedDecisionPreservesCoordinatorMetadata() async {
        let snapshot = SumiSystemPermissionSnapshot(kind: .camera, state: .denied)
        let coordinatorDecision = SumiPermissionCoordinatorDecision(
            outcome: .systemBlocked,
            state: .deny,
            persistence: .session,
            source: .system,
            reason: "system-blocked",
            permissionTypes: [.camera],
            systemAuthorizationSnapshot: snapshot,
            shouldOfferSystemSettings: true
        )
        let coordinator = FakePermissionCoordinator(mode: .immediate(coordinatorDecision))
        let bridge = makeBridge(coordinator: coordinator)

        let decisions = await resolve(bridge: bridge, request: mediaRequest(permissionTypes: [.camera]))

        XCTAssertEqual(decisions, [.deny])
        let observedDecision = await coordinator.lastReturnedDecision()
        XCTAssertEqual(observedDecision?.systemAuthorizationSnapshot, snapshot)
        XCTAssertTrue(observedDecision?.shouldOfferSystemSettings == true)
    }

    func testPendingPromptRequiredUsesTemporaryDenyStrategy() async {
        let coordinator = FakePermissionCoordinator(mode: .pending)
        let bridge = makeBridge(
            coordinator: coordinator,
            pendingPollIntervalNanoseconds: 1_000_000,
            coordinatorTimeoutNanoseconds: 50_000_000
        )

        let decisions = await resolve(bridge: bridge, request: mediaRequest(permissionTypes: [.camera]))

        XCTAssertEqual(decisions, [.deny])
        let cancelledReasons = await coordinator.cancelledReasons()
        XCTAssertEqual(cancelledReasons, ["webkit-media-prompt-ui-unavailable-deny"])
    }

    func testExactlyOnceCallbackForImmediateGrantDenySystemBlockedAndTimeout() async {
        let grantBridge = makeBridge(
            coordinator: FakePermissionCoordinator(mode: .immediate(decision(.granted, reason: "stored-allow")))
        )
        let grantDecisions = await resolve(bridge: grantBridge, request: mediaRequest(permissionTypes: [.camera]))
        XCTAssertEqual(grantDecisions, [.grant])

        let denyBridge = makeBridge(
            coordinator: FakePermissionCoordinator(mode: .immediate(decision(.denied, reason: "stored-deny")))
        )
        let denyDecisions = await resolve(bridge: denyBridge, request: mediaRequest(permissionTypes: [.camera]))
        XCTAssertEqual(denyDecisions, [.deny])

        let blockedBridge = makeBridge(
            coordinator: FakePermissionCoordinator(mode: .immediate(decision(.systemBlocked, reason: "system")))
        )
        let blockedDecisions = await resolve(bridge: blockedBridge, request: mediaRequest(permissionTypes: [.camera]))
        XCTAssertEqual(blockedDecisions, [.deny])

        let timeoutBridge = makeBridge(
            coordinator: FakePermissionCoordinator(mode: .neverCompletesWithoutQuery),
            pendingPollIntervalNanoseconds: 1_000_000,
            coordinatorTimeoutNanoseconds: 5_000_000
        )
        let timeoutDecisions = await resolve(bridge: timeoutBridge, request: mediaRequest(permissionTypes: [.camera]))
        XCTAssertEqual(timeoutDecisions, [.deny])
    }

    func testExactlyOnceWrapperIgnoresDuplicateResolutions() {
        var decisions: [WKPermissionDecision] = []
        let once = SumiWebKitPermissionDecisionHandler {
            decisions.append($0)
        }

        once.resolve(.grant)
        once.resolve(.deny)

        XCTAssertEqual(decisions, [.grant])
    }

    func testUnavailableWebViewDeniesOnceWithoutHanging() async {
        let bridge = makeBridge(
            coordinator: FakePermissionCoordinator(mode: .immediate(decision(.granted, reason: "stored-allow")))
        )
        let expectation = XCTestExpectation(description: "Unavailable WebView deny")
        var decisions: [WKPermissionDecision] = []

        bridge.handleMediaCaptureAuthorization(
            mediaRequest(permissionTypes: [.camera]),
            tabContext: tabContext(),
            webView: nil
        ) { decision in
            decisions.append(decision)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(decisions, [.deny])
    }

    func testStoreWriteBehaviorForBlocksPendingAndStoredDecisions() async {
        let hardDenyStore = BridgePermissionStore()
        let hardDenyBridge = realCoordinatorBridge(
            policyResult: .hardDeny(decision: permissionDecision(.deny, source: .policy, reason: "policy-deny")),
            store: hardDenyStore
        )
        let hardDenyDecisions = await resolve(bridge: hardDenyBridge, request: mediaRequest(permissionTypes: [.camera]))
        XCTAssertEqual(hardDenyDecisions, [.deny])
        let hardDenySetCount = await hardDenyStore.setDecisionCallCount()
        XCTAssertEqual(hardDenySetCount, 0)

        let systemBlockedStore = BridgePermissionStore()
        let snapshot = SumiSystemPermissionSnapshot(kind: .camera, state: .denied)
        let systemBlockedBridge = realCoordinatorBridge(
            policyResult: .systemBlocked(
                snapshot: snapshot,
                decision: permissionDecision(.deny, source: .system, reason: "system-blocked")
            ),
            store: systemBlockedStore
        )
        let systemBlockedDecisions = await resolve(
            bridge: systemBlockedBridge,
            request: mediaRequest(permissionTypes: [.camera])
        )
        XCTAssertEqual(systemBlockedDecisions, [.deny])
        let systemBlockedSetCount = await systemBlockedStore.setDecisionCallCount()
        XCTAssertEqual(systemBlockedSetCount, 0)

        let pendingStore = BridgePermissionStore()
        let pendingBridge = realCoordinatorBridge(
            policyResult: proceedPolicyResult(),
            store: pendingStore,
            pendingPollIntervalNanoseconds: 1_000_000,
            coordinatorTimeoutNanoseconds: 50_000_000
        )
        let pendingDecisions = await resolve(bridge: pendingBridge, request: mediaRequest(permissionTypes: [.camera]))
        XCTAssertEqual(pendingDecisions, [.deny])
        let pendingSetCount = await pendingStore.setDecisionCallCount()
        XCTAssertEqual(pendingSetCount, 0)

        let allowStore = BridgePermissionStore()
        await allowStore.seed(
            key(.camera),
            decision: permissionDecision(.allow, persistence: .persistent, source: .user, reason: "stored-allow")
        )
        let allowBridge = realCoordinatorBridge(policyResult: proceedPolicyResult(), store: allowStore)
        let allowDecisions = await resolve(bridge: allowBridge, request: mediaRequest(permissionTypes: [.camera]))
        XCTAssertEqual(allowDecisions, [.grant])

        let denyStore = BridgePermissionStore()
        await denyStore.seed(
            key(.camera),
            decision: permissionDecision(.deny, persistence: .persistent, source: .user, reason: "stored-deny")
        )
        let denyBridge = realCoordinatorBridge(policyResult: proceedPolicyResult(), store: denyStore)
        let storedDenyDecisions = await resolve(bridge: denyBridge, request: mediaRequest(permissionTypes: [.camera]))
        XCTAssertEqual(storedDenyDecisions, [.deny])
    }

    func testRuntimeControllerBoundary() async {
        let grantRuntime = FakeSumiRuntimePermissionController()
        let grantBridge = makeBridge(
            coordinator: FakePermissionCoordinator(mode: .immediate(decision(.granted, reason: "stored-allow"))),
            runtimeController: grantRuntime
        )

        let runtimeGrantDecisions = await resolve(bridge: grantBridge, request: mediaRequest(permissionTypes: [.camera]))
        XCTAssertEqual(runtimeGrantDecisions, [.grant])
        XCTAssertEqual(grantRuntime.currentRuntimeStateCallCount, 1)
        XCTAssertEqual(grantRuntime.resumeRuntimePermissionsCallCount, 0)
        XCTAssertEqual(grantRuntime.revokeRuntimePermissionsCallCount, 0)

        let denyRuntime = FakeSumiRuntimePermissionController(cameraRuntimeState: .active)
        let denyBridge = makeBridge(
            coordinator: FakePermissionCoordinator(mode: .immediate(decision(.denied, reason: "stored-deny"))),
            runtimeController: denyRuntime
        )

        let runtimeDenyDecisions = await resolve(bridge: denyBridge, request: mediaRequest(permissionTypes: [.camera]))
        XCTAssertEqual(runtimeDenyDecisions, [.deny])
        XCTAssertEqual(denyRuntime.currentRuntimeStateCallCount, 0)
        XCTAssertEqual(denyRuntime.revokeRuntimePermissionsCallCount, 0)
        XCTAssertEqual(denyRuntime.cameraRuntimeState, .active)
    }

    func testNormalTabUIDelegateRoutesMediaThroughBridge() throws {
        let source = try sourceFile("Sumi/Models/Tab/Tab+UIDelegate.swift")
        let mediaMethodStart = source.range(of: "requestMediaCaptureAuthorization type: WKMediaCaptureType")!
        let methodSource = String(source[mediaMethodStart.lowerBound...])

        XCTAssertTrue(methodSource.contains("webKitPermissionBridge.handleMediaCaptureAuthorization("))
        XCTAssertFalse(methodSource.contains("decisionHandler(.grant)"))
    }

    private func makeBridge(
        coordinator: any SumiPermissionCoordinating,
        runtimeController: FakeSumiRuntimePermissionController? = nil,
        pendingPollIntervalNanoseconds: UInt64 = 1_000_000,
        coordinatorTimeoutNanoseconds: UInt64 = 100_000_000
    ) -> SumiWebKitPermissionBridge {
        SumiWebKitPermissionBridge(
            coordinator: coordinator,
            runtimeController: runtimeController ?? FakeSumiRuntimePermissionController(),
            pendingPollIntervalNanoseconds: pendingPollIntervalNanoseconds,
            coordinatorTimeoutNanoseconds: coordinatorTimeoutNanoseconds,
            now: { self.fixedDate }
        )
    }

    private func realCoordinatorBridge(
        policyResult: SumiPermissionPolicyResult,
        store: BridgePermissionStore,
        pendingPollIntervalNanoseconds: UInt64 = 1_000_000,
        coordinatorTimeoutNanoseconds: UInt64 = 100_000_000
    ) -> SumiWebKitPermissionBridge {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: BridgePolicyResolver(result: policyResult),
            persistentStore: store,
            now: { self.fixedDate }
        )
        return makeBridge(
            coordinator: coordinator,
            pendingPollIntervalNanoseconds: pendingPollIntervalNanoseconds,
            coordinatorTimeoutNanoseconds: coordinatorTimeoutNanoseconds
        )
    }

    private func resolve(
        bridge: SumiWebKitPermissionBridge,
        request: SumiWebKitMediaCaptureRequest,
        tabContext: SumiWebKitMediaCaptureTabContext? = nil
    ) async -> [WKPermissionDecision] {
        let expectation = XCTestExpectation(description: "WebKit media decision")
        let webView = WKWebView()
        var decisions: [WKPermissionDecision] = []
        bridge.handleMediaCaptureAuthorization(
            request,
            tabContext: tabContext ?? self.tabContext(),
            webView: webView
        ) { decision in
            decisions.append(decision)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)
        withExtendedLifetime(webView) {}
        return decisions
    }

    private func mediaRequest(
        permissionTypes: [SumiPermissionType],
        requestingOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://example.com"),
        isMainFrame: Bool = true
    ) -> SumiWebKitMediaCaptureRequest {
        SumiWebKitMediaCaptureRequest(
            id: "request-a",
            webKitMediaTypeRawValue: 0,
            permissionTypes: permissionTypes,
            requestingOrigin: requestingOrigin,
            frameURL: URL(string: "https://example.com/frame"),
            isMainFrame: isMainFrame
        )
    }

    private func tabContext(
        tabId: String = "tab-a",
        pageId: String = "tab-a:1",
        profilePartitionId: String = "profile-a",
        isEphemeralProfile: Bool = false,
        committedURL: URL? = URL(string: "https://example.com"),
        visibleURL: URL? = URL(string: "https://example.com/path"),
        mainFrameURL: URL? = URL(string: "https://example.com"),
        isActiveTab: Bool = true,
        isVisibleTab: Bool = true,
        navigationOrPageGeneration: String? = "1"
    ) -> SumiWebKitMediaCaptureTabContext {
        SumiWebKitMediaCaptureTabContext(
            tabId: tabId,
            pageId: pageId,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile,
            committedURL: committedURL,
            visibleURL: visibleURL,
            mainFrameURL: mainFrameURL,
            isActiveTab: isActiveTab,
            isVisibleTab: isVisibleTab,
            navigationOrPageGeneration: navigationOrPageGeneration
        )
    }

    private func key(_ permissionType: SumiPermissionType) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            permissionType: permissionType,
            profilePartitionId: "profile-a",
            transientPageId: "tab-a:1",
            isEphemeralProfile: false
        )
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

@available(macOS 13.0, *)
private actor FakePermissionCoordinator: SumiPermissionCoordinating {
    enum Mode {
        case immediate(SumiPermissionCoordinatorDecision)
        case pending
        case neverCompletesWithoutQuery
    }

    private let mode: Mode
    private var contexts: [SumiPermissionSecurityContext] = []
    private var activeQueries: [String: SumiPermissionAuthorizationQuery] = [:]
    private var continuations: [String: CheckedContinuation<SumiPermissionCoordinatorDecision, Never>] = [:]
    private var cancelReasons: [String] = []
    private var returnedDecision: SumiPermissionCoordinatorDecision?

    init(mode: Mode) {
        self.mode = mode
    }

    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        switch mode {
        case .immediate(let decision):
            returnedDecision = decision
            return decision
        case .pending:
            let query = authorizationQuery(for: context)
            activeQueries[query.pageId] = query
            return await withCheckedContinuation { continuation in
                continuations[context.request.id] = continuation
            }
        case .neverCompletesWithoutQuery:
            return await withCheckedContinuation { continuation in
                continuations[context.request.id] = continuation
            }
        }
    }

    func activeQuery(forPageId pageId: String) -> SumiPermissionAuthorizationQuery? {
        activeQueries[pageId]
    }

    @discardableResult
    func cancel(
        requestId: String,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        cancelReasons.append(reason)
        let context = contexts.first { $0.request.id == requestId }
        let decision = SumiWebKitMediaCaptureDecisionMapper.failClosedDecision(
            for: context,
            reason: reason
        )
        returnedDecision = decision
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
        return SumiWebKitMediaCaptureDecisionMapper.failClosedDecision(
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
        return SumiWebKitMediaCaptureDecisionMapper.failClosedDecision(
            for: nil,
            reason: reason
        )
    }

    func cancelledReasons() -> [String] {
        cancelReasons
    }

    func lastReturnedDecision() -> SumiPermissionCoordinatorDecision? {
        returnedDecision
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
            permissionTypes: context.request.permissionTypes,
            presentationPermissionType: nil,
            availablePersistences: [.oneTime, .session, .persistent],
            defaultPersistence: .oneTime,
            systemAuthorizationSnapshots: [],
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

private actor BridgePolicyResolver: SumiPermissionPolicyResolver {
    private let result: SumiPermissionPolicyResult

    init(result: SumiPermissionPolicyResult) {
        self.result = result
    }

    func evaluate(_ context: SumiPermissionSecurityContext) async -> SumiPermissionPolicyResult {
        result
    }
}

private actor BridgePermissionStore: SumiPermissionStore {
    private var records: [String: SumiPermissionStoreRecord] = [:]
    private var setCount = 0

    func seed(_ key: SumiPermissionKey, decision: SumiPermissionDecision) {
        records[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord? {
        records[key.persistentIdentity]
    }

    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async throws {
        setCount += 1
        records[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func resetDecision(for key: SumiPermissionKey) async throws {
        records.removeValue(forKey: key.persistentIdentity)
    }

    func listDecisions(profilePartitionId: String) async throws -> [SumiPermissionStoreRecord] {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return records.values.filter { $0.key.profilePartitionId == profileId }
    }

    func listDecisions(
        forDisplayDomain displayDomain: String,
        profilePartitionId: String
    ) async throws -> [SumiPermissionStoreRecord] {
        let domain = SumiPermissionStoreRecord.normalizedDisplayDomain(displayDomain)
        return try await listDecisions(profilePartitionId: profilePartitionId)
            .filter { $0.displayDomain == domain }
    }

    func clearAll(profilePartitionId: String) async throws {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        records = records.filter { _, record in record.key.profilePartitionId != profileId }
    }

    func clearForDisplayDomains(
        _ displayDomains: Set<String>,
        profilePartitionId: String
    ) async throws {
        let domains = Set(displayDomains.map(SumiPermissionStoreRecord.normalizedDisplayDomain))
        records = records.filter { _, record in !domains.contains(record.displayDomain) }
    }

    func clearForOrigins(
        _ origins: Set<SumiPermissionOrigin>,
        profilePartitionId: String
    ) async throws {
        let identities = Set(origins.map(\.identity))
        records = records.filter { _, record in
            !identities.contains(record.key.requestingOrigin.identity)
                && !identities.contains(record.key.topOrigin.identity)
        }
    }

    @discardableResult
    func expireDecisions(now: Date) async throws -> Int {
        0
    }

    func recordLastUsed(for key: SumiPermissionKey, at date: Date) async throws {}

    func setDecisionCallCount() -> Int {
        setCount
    }
}

private func decision(
    _ outcome: SumiPermissionCoordinatorOutcome,
    reason: String
) -> SumiPermissionCoordinatorDecision {
    SumiPermissionCoordinatorDecision(
        outcome: outcome,
        state: outcome == .granted ? .allow : .deny,
        persistence: outcome == .granted || outcome == .denied ? .persistent : nil,
        source: outcome == .systemBlocked ? .system : .user,
        reason: reason,
        permissionTypes: [.camera],
        keys: [],
        shouldPersist: false
    )
}

private func permissionDecision(
    _ state: SumiPermissionState,
    persistence: SumiPermissionPersistence = .session,
    source: SumiPermissionDecisionSource,
    reason: String
) -> SumiPermissionDecision {
    SumiPermissionDecision(
        state: state,
        persistence: persistence,
        source: source,
        reason: reason,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

private func proceedPolicyResult() -> SumiPermissionPolicyResult {
    .proceed(
        source: .defaultSetting,
        reason: SumiPermissionPolicyReason.allowed,
        systemAuthorizationSnapshot: SumiSystemPermissionSnapshot(kind: .camera, state: .authorized),
        mayOpenSystemSettings: false,
        requiresSystemAuthorizationPrompt: false,
        allowedPersistences: [.oneTime, .session, .persistent]
    )
}
