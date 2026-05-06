import WebKit
import XCTest

@testable import Sumi

private let webKitGeolocationBridgeFixedDate = Date(timeIntervalSince1970: 1_800_000_000)

@available(macOS 12.0, *)
@MainActor
final class SumiWebKitGeolocationBridgeTests: XCTestCase {
    func testSecurityContextConstructionUsesTrustedBrowserData() {
        let provider = FakeSumiGeolocationProvider()
        let bridge = makeBridge(
            coordinator: FakeGeolocationPermissionCoordinator(
                mode: .immediate(decision(.denied, reason: "test-deny"))
            ),
            provider: provider
        )
        let context = bridge.securityContext(
            for: geolocationRequest(requestingOrigin: SumiPermissionOrigin(string: "https://geo.example")),
            tabContext: tabContext(
                profilePartitionId: "Profile-A",
                isEphemeralProfile: true,
                committedURL: URL(string: "https://top.example/path")!,
                visibleURL: URL(string: "https://visible.example/path")!
            )
        )

        XCTAssertEqual(context.surface, .normalTab)
        XCTAssertEqual(context.requestingOrigin.identity, "https://geo.example")
        XCTAssertEqual(context.topOrigin.identity, "https://top.example")
        XCTAssertEqual(context.profilePartitionId, "profile-a")
        XCTAssertTrue(context.isEphemeralProfile)
        XCTAssertEqual(context.committedURL?.host(), "top.example")
        XCTAssertEqual(context.visibleURL?.host(), "visible.example")
        XCTAssertEqual(context.transientPageId, "tab-a:1")
        XCTAssertEqual(context.request.displayDomain, "geo.example")
    }

    func testCoordinatorDecisionMappingAndProviderRegistration() async {
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

        for (outcome, expectedDecision) in outcomes {
            let provider = FakeSumiGeolocationProvider()
            let bridge = makeBridge(
                coordinator: FakeGeolocationPermissionCoordinator(
                    mode: .immediate(decision(outcome, reason: "decision-\(outcome.rawValue)"))
                ),
                provider: provider
            )

            let decisions = await resolve(bridge: bridge)

            XCTAssertEqual(decisions, [expectedDecision], "outcome \(outcome)")
            XCTAssertEqual(provider.registeredRequests.count, expectedDecision == .grant ? 1 : 0)
        }
    }

    func testUnavailableProviderDenyAfterCoordinatorGrant() async {
        let provider = FakeSumiGeolocationProvider(currentState: .unavailable)
        let bridge = makeBridge(
            coordinator: FakeGeolocationPermissionCoordinator(
                mode: .immediate(decision(.granted, reason: "stored-allow"))
            ),
            provider: provider
        )

        let decisions = await resolve(bridge: bridge)

        XCTAssertEqual(decisions, [.deny])
        XCTAssertTrue(provider.registeredRequests.isEmpty)
    }

    func testPendingPromptRequiredUsesPromptPresenterUnavailableDenyStrategy() async {
        let coordinator = FakeGeolocationPermissionCoordinator(mode: .pending)
        let bridge = makeBridge(
            coordinator: coordinator,
            provider: FakeSumiGeolocationProvider(),
            pendingPollIntervalNanoseconds: 1_000_000,
            coordinatorTimeoutNanoseconds: 50_000_000
        )

        let decisions = await resolve(bridge: bridge)
        let cancelledReasons = await coordinator.cancelledReasons()

        XCTAssertEqual(decisions, [.deny])
        XCTAssertEqual(cancelledReasons, ["webkit-geolocation-prompt-presenter-unavailable-deny"])
    }

    func testSystemStatesMapWithoutRequestingAuthorizationOrPersistingSiteDeny() async {
        let blockedStore = GeolocationBridgePermissionStore()
        let blockedSystem = FakeSumiSystemPermissionService(states: [.geolocation: .denied])
        let blockedBridge = realCoordinatorBridge(
            systemService: blockedSystem,
            store: blockedStore,
            provider: FakeSumiGeolocationProvider()
        )

        let blockedDecisions = await resolve(bridge: blockedBridge)
        let blockedStoreWrites = await blockedStore.setDecisionCallCount()
        let blockedAuthorizationRequests = await blockedSystem.requestAuthorizationCallCount(for: .geolocation)

        XCTAssertEqual(blockedDecisions, [.deny])
        XCTAssertEqual(blockedStoreWrites, 0)
        XCTAssertEqual(blockedAuthorizationRequests, 0)

        let pendingStore = GeolocationBridgePermissionStore()
        let pendingSystem = FakeSumiSystemPermissionService(states: [.geolocation: .notDetermined])
        let pendingBridge = realCoordinatorBridge(
            systemService: pendingSystem,
            store: pendingStore,
            provider: FakeSumiGeolocationProvider(),
            pendingPollIntervalNanoseconds: 1_000_000,
            coordinatorTimeoutNanoseconds: 50_000_000
        )

        let pendingDecisions = await resolve(bridge: pendingBridge)
        let pendingStoreWrites = await pendingStore.setDecisionCallCount()
        let pendingAuthorizationRequests = await pendingSystem.requestAuthorizationCallCount(for: .geolocation)

        XCTAssertEqual(pendingDecisions, [.deny])
        XCTAssertEqual(pendingStoreWrites, 0)
        XCTAssertEqual(pendingAuthorizationRequests, 0)
    }

    func testStoredAllowGrantsWhenSystemAuthorizedAndProviderAvailable() async {
        let store = GeolocationBridgePermissionStore()
        await store.seed(
            key(.geolocation),
            decision: permissionDecision(.allow, persistence: .persistent, source: .user, reason: "stored-allow")
        )
        let provider = FakeSumiGeolocationProvider()
        let bridge = realCoordinatorBridge(
            systemService: FakeSumiSystemPermissionService(states: [.geolocation: .authorized]),
            store: store,
            provider: provider
        )

        let decisions = await resolve(bridge: bridge)

        XCTAssertEqual(decisions, [.grant])
        XCTAssertEqual(provider.registeredRequests.map(\.pageId), ["tab-a:1"])
    }

    func testMissingTrustworthyOriginFailsClosedThroughCoordinator() async {
        let store = GeolocationBridgePermissionStore()
        let bridge = realCoordinatorBridge(
            systemService: FakeSumiSystemPermissionService(states: [.geolocation: .authorized]),
            store: store,
            provider: FakeSumiGeolocationProvider()
        )

        let decisions = await resolve(
            bridge: bridge,
            request: geolocationRequest(requestingOrigin: .invalid(reason: "missing-origin")),
            tabContext: tabContext(committedURL: nil, visibleURL: nil, mainFrameURL: nil)
        )

        XCTAssertEqual(decisions, [.deny])
        let storeWrites = await store.setDecisionCallCount()
        XCTAssertEqual(storeWrites, 0)
    }

    func testLegacyBoolDecisionHandlerMapsGrantAndDenyExactlyOnce() async {
        let provider = FakeSumiGeolocationProvider()
        let bridge = makeBridge(
            coordinator: FakeGeolocationPermissionCoordinator(
                mode: .immediate(decision(.granted, reason: "stored-allow"))
            ),
            provider: provider
        )
        let expectation = XCTestExpectation(description: "Legacy geolocation decision")
        var decisions: [Bool] = []
        let webView = WKWebView()

        bridge.handleLegacyGeolocationAuthorization(
            geolocationRequest(),
            tabContext: tabContext(),
            webView: webView
        ) { decision in
            decisions.append(decision)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(decisions, [true])
    }

    func testExactlyOnceWrapperIgnoresDuplicateResolutions() {
        var decisions: [Bool] = []
        let once = SumiWebKitGeolocationOnce<Bool> {
            decisions.append($0)
        }

        once.resolve(true)
        once.resolve(false)

        XCTAssertEqual(decisions, [true])
    }

    func testUnavailableWebViewDeniesOnceWithoutHanging() async {
        let bridge = makeBridge(
            coordinator: FakeGeolocationPermissionCoordinator(
                mode: .immediate(decision(.granted, reason: "stored-allow"))
            ),
            provider: FakeSumiGeolocationProvider()
        )
        let expectation = XCTestExpectation(description: "Unavailable WebView deny")
        var decisions: [WKPermissionDecision] = []

        bridge.handleGeolocationAuthorization(
            geolocationRequest(),
            tabContext: tabContext(),
            webView: nil
        ) { decision in
            decisions.append(decision)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(decisions, [.deny])
    }

    func testNormalTabUIDelegateRoutesPrivateGeolocationSelectorsThroughBridge() throws {
        let source = try sourceFile("Sumi/Models/Tab/Tab+UIDelegate.swift")

        XCTAssertTrue(source.contains("_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:"))
        XCTAssertTrue(source.contains("_webView:requestGeolocationPermissionForFrame:decisionHandler:"))
        XCTAssertTrue(source.contains("webKitGeolocationBridge.handleGeolocationAuthorization("))
        XCTAssertTrue(source.contains("webKitGeolocationBridge.handleLegacyGeolocationAuthorization("))
    }

    private func makeBridge(
        coordinator: any SumiPermissionCoordinating,
        provider: FakeSumiGeolocationProvider?,
        pendingStrategy: SumiWebKitGeolocationPendingStrategy = .promptPresenterUnavailableDeny,
        pendingPollIntervalNanoseconds: UInt64 = 1_000_000,
        coordinatorTimeoutNanoseconds: UInt64 = 100_000_000
    ) -> SumiWebKitGeolocationBridge {
        SumiWebKitGeolocationBridge(
            coordinator: coordinator,
            geolocationProvider: provider,
            pendingStrategy: pendingStrategy,
            pendingPollIntervalNanoseconds: pendingPollIntervalNanoseconds,
            coordinatorTimeoutNanoseconds: coordinatorTimeoutNanoseconds,
            now: { webKitGeolocationBridgeFixedDate }
        )
    }

    private func realCoordinatorBridge(
        systemService: FakeSumiSystemPermissionService,
        store: GeolocationBridgePermissionStore,
        provider: FakeSumiGeolocationProvider,
        pendingStrategy: SumiWebKitGeolocationPendingStrategy = .promptPresenterUnavailableDeny,
        pendingPollIntervalNanoseconds: UInt64 = 1_000_000,
        coordinatorTimeoutNanoseconds: UInt64 = 100_000_000
    ) -> SumiWebKitGeolocationBridge {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: systemService
            ),
            persistentStore: store,
            now: { webKitGeolocationBridgeFixedDate }
        )
        return makeBridge(
            coordinator: coordinator,
            provider: provider,
            pendingStrategy: pendingStrategy,
            pendingPollIntervalNanoseconds: pendingPollIntervalNanoseconds,
            coordinatorTimeoutNanoseconds: coordinatorTimeoutNanoseconds
        )
    }

    private func resolve(
        bridge: SumiWebKitGeolocationBridge,
        request: SumiWebKitGeolocationRequest? = nil,
        tabContext: SumiWebKitGeolocationTabContext? = nil
    ) async -> [WKPermissionDecision] {
        let expectation = XCTestExpectation(description: "WebKit geolocation decision")
        let webView = WKWebView()
        var decisions: [WKPermissionDecision] = []
        bridge.handleGeolocationAuthorization(
            request ?? geolocationRequest(),
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

    private func geolocationRequest(
        requestingOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://example.com"),
        isMainFrame: Bool = true
    ) -> SumiWebKitGeolocationRequest {
        SumiWebKitGeolocationRequest(
            id: "request-a",
            requestingOrigin: requestingOrigin,
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
    ) -> SumiWebKitGeolocationTabContext {
        SumiWebKitGeolocationTabContext(
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

@available(macOS 12.0, *)
private actor FakeGeolocationPermissionCoordinator: SumiPermissionCoordinating {
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

    init(mode: Mode) {
        self.mode = mode
    }

    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        switch mode {
        case .immediate(let decision):
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

    func queryPermissionState(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        switch mode {
        case .immediate(let decision):
            return decision
        case .pending, .neverCompletesWithoutQuery:
            return SumiPermissionCoordinatorDecision(
                outcome: .promptRequired,
                state: .ask,
                persistence: nil,
                source: .runtime,
                reason: "fake-query-prompt-required",
                permissionTypes: context.request.permissionTypes,
                keys: context.request.permissionTypes.map { context.request.key(for: $0) },
                disablesPersistentAllow: context.isEphemeralProfile
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
        let decision = SumiWebKitGeolocationDecisionMapper.failClosedDecision(
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
    func cancel(pageId: String, reason: String) -> SumiPermissionCoordinatorDecision {
        cancelReasons.append(reason)
        activeQueries[pageId] = nil
        return SumiWebKitGeolocationDecisionMapper.failClosedDecision(for: nil, reason: reason)
    }

    @discardableResult
    func cancelNavigation(pageId: String, reason: String) -> SumiPermissionCoordinatorDecision {
        cancel(pageId: pageId, reason: reason)
    }

    @discardableResult
    func cancelTab(tabId: String, reason: String) -> SumiPermissionCoordinatorDecision {
        cancelReasons.append(reason)
        return SumiWebKitGeolocationDecisionMapper.failClosedDecision(for: nil, reason: reason)
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
            permissionTypes: [.geolocation],
            presentationPermissionType: nil,
            availablePersistences: [.oneTime, .session, .persistent],
            systemAuthorizationSnapshots: [],
            policyReasons: [SumiPermissionPolicyReason.allowed],
            createdAt: context.now,
            isEphemeralProfile: context.isEphemeralProfile,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context.isEphemeralProfile
    )
    }
}

private actor GeolocationBridgePermissionStore: SumiPermissionStore {
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
        permissionTypes: [.geolocation],
        keys: []
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
