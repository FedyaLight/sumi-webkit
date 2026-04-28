import XCTest

@testable import Sumi

@MainActor
final class SumiExternalSchemePermissionBridgeTests: XCTestCase {
    func testSchemeClassificationCoversActivationRedirectBackgroundAndInternalCases() {
        XCTAssertEqual(
            SumiExternalSchemePermissionRequest.classify(
                targetURL: URL(string: "mailto:test@example.com"),
                userActivation: .navigationAction,
                isRedirectChain: false
            ),
            .directUserActivated
        )
        XCTAssertEqual(
            SumiExternalSchemePermissionRequest.classify(
                targetURL: URL(string: "zoommtg://join/123"),
                userActivation: .navigationAction,
                isRedirectChain: false
            ),
            .directUserActivated
        )
        XCTAssertEqual(
            SumiExternalSchemePermissionRequest.classify(
                targetURL: URL(string: "mailto:test@example.com"),
                userActivation: .none,
                isRedirectChain: false
            ),
            .scriptOrBackground
        )
        XCTAssertEqual(
            SumiExternalSchemePermissionRequest.classify(
                targetURL: URL(string: "facetime:user@example.com"),
                userActivation: .redirectChain,
                isRedirectChain: true
            ),
            .redirectChainUserActivated
        )
        XCTAssertEqual(
            SumiExternalSchemePermissionRequest.classify(
                targetURL: URL(string: "maps://?q=cupertino"),
                userActivation: .unknown,
                isRedirectChain: true
            ),
            .redirectChainBackground
        )
        XCTAssertEqual(
            SumiExternalSchemePermissionRequest.classify(
                targetURL: nil,
                userActivation: .unknown,
                isRedirectChain: false
            ),
            .unknownOrUnsupported
        )
        XCTAssertEqual(
            SumiExternalSchemePermissionRequest.classify(
                targetURL: URL(string: "sumi://settings"),
                userActivation: .navigationAction,
                isRedirectChain: false
            ),
            .internalOrBrowserOwned
        )
        XCTAssertFalse(SumiExternalSchemePermissionRequest.isValidExternalSchemeURL(URL(string: "sumi://settings")!))
        XCTAssertFalse(SumiExternalSchemePermissionRequest.isValidExternalSchemeURL(URL(string: "https://example.com")!))
    }

    func testStoredAllowOpensExternalAppAndRecordsResolverMetadata() async {
        let mailURL = URL(string: "mailto:test@example.com?subject=secret#frag")!
        let store = ExternalSchemeBridgePermissionStore()
        await store.seed(
            externalKey(scheme: "mailto"),
            decision: externalDecision(.allow, persistence: .persistent, reason: "stored-allow")
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"], appDisplayName: "Mail")
        var events: [SumiExternalSchemePermissionEvent] = []
        let bridge = realExternalBridge(store: store, resolver: resolver) { events.append($0) }
        var willOpenCalled = false

        let result = await bridge.evaluate(
            externalRequest(targetURL: mailURL, userActivation: .navigationAction),
            tabContext: externalTabContext(),
            willOpen: { willOpenCalled = true }
        )

        XCTAssertTrue(result.didOpen)
        XCTAssertTrue(willOpenCalled)
        XCTAssertEqual(resolver.openedURLs, [mailURL])
        XCTAssertEqual(result.record?.result, .opened)
        XCTAssertEqual(result.record?.scheme, "mailto")
        XCTAssertEqual(result.record?.appDisplayName, "Mail")
        XCTAssertEqual(result.record?.redactedTargetURLString, "mailto:test@example.com")
        XCTAssertFalse(result.record?.redactedTargetURLString?.contains("secret") == true)
        XCTAssertTrue(events.contains(.opened(requestId: "external-a", pageId: "tab-a:1", scheme: "mailto")))
    }

    func testStoredDenyBlocksAndDoesNotOpen() async {
        let store = ExternalSchemeBridgePermissionStore()
        await store.seed(
            externalKey(scheme: "mailto"),
            decision: externalDecision(.deny, persistence: .persistent, reason: "stored-deny")
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = realExternalBridge(store: store, resolver: resolver)

        let result = await bridge.evaluate(
            externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .navigationAction),
            tabContext: externalTabContext()
        )

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.result, .blockedByStoredDeny)
        XCTAssertEqual(result.reason, "stored-persistent-deny")
        XCTAssertTrue(resolver.openedURLs.isEmpty)
    }

    func testUserActivatedNoDecisionBlocksPendingUIWithoutPersistingDeny() async {
        let store = ExternalSchemeBridgePermissionStore()
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = realExternalBridge(store: store, resolver: resolver)

        let result = await bridge.evaluate(
            externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .navigationAction),
            tabContext: externalTabContext()
        )

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.result, .blockedPendingUI)
        XCTAssertEqual(result.reason, SumiExternalSchemePendingStrategy.blockUntilPromptUIExists.reason)
        XCTAssertEqual(result.coordinatorDecision?.shouldPersist, false)
        XCTAssertTrue(resolver.openedURLs.isEmpty)
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
    }

    func testBackgroundNoDecisionBlocksByDefaultWithoutPersistingDeny() async {
        let store = ExternalSchemeBridgePermissionStore()
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = realExternalBridge(store: store, resolver: resolver)

        let result = await bridge.evaluate(
            externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .none),
            tabContext: externalTabContext()
        )

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.result, .blockedByDefault)
        XCTAssertEqual(result.reason, "external-scheme-background-default-block")
        XCTAssertTrue(resolver.openedURLs.isEmpty)
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
    }

    func testUnknownActivationIsConservativeAndBlocksPendingPromptUI() async {
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = realExternalBridge(store: ExternalSchemeBridgePermissionStore(), resolver: resolver)

        let result = await bridge.evaluate(
            externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .unknown),
            tabContext: externalTabContext()
        )

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.result, .blockedByDefault)
        XCTAssertTrue(resolver.openedURLs.isEmpty)
    }

    func testPersistentAllowIsKeyedBySiteAndScheme() async {
        let store = ExternalSchemeBridgePermissionStore()
        await store.seed(
            externalKey(scheme: "mailto"),
            decision: externalDecision(.allow, persistence: .persistent, reason: "stored-allow")
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto", "zoommtg"])
        let bridge = realExternalBridge(store: store, resolver: resolver)
        let mailURL = URL(string: "mailto:test@example.com")!
        let zoomURL = URL(string: "zoommtg://join/123")!

        let allowedMail = await bridge.evaluate(
            externalRequest(id: "mail", targetURL: mailURL, userActivation: .navigationAction),
            tabContext: externalTabContext()
        )
        let otherScheme = await bridge.evaluate(
            externalRequest(id: "zoom", targetURL: zoomURL, userActivation: .navigationAction),
            tabContext: externalTabContext()
        )
        let otherSite = await bridge.evaluate(
            externalRequest(
                id: "other-site",
                targetURL: mailURL,
                requestingOrigin: SumiPermissionOrigin(string: "https://other.example"),
                userActivation: .navigationAction
            ),
            tabContext: externalTabContext()
        )

        XCTAssertTrue(allowedMail.didOpen)
        XCTAssertEqual(otherScheme.record?.result, .blockedPendingUI)
        XCTAssertEqual(otherSite.record?.result, .blockedPendingUI)
        XCTAssertEqual(resolver.openedURLs, [mailURL])
    }

    func testStoredAskUsesTemporaryStrategyWithoutStoreWrite() async {
        let store = ExternalSchemeBridgePermissionStore()
        await store.seed(
            externalKey(scheme: "mailto"),
            decision: externalDecision(.ask, persistence: .persistent, reason: "stored-ask")
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = realExternalBridge(store: store, resolver: resolver)

        let result = await bridge.evaluate(
            externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .navigationAction),
            tabContext: externalTabContext()
        )

        XCTAssertEqual(result.record?.result, .blockedPendingUI)
        XCTAssertEqual(result.reason, SumiExternalSchemePendingStrategy.blockUntilPromptUIExists.reason)
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
    }

    func testSessionAllowOpensBackgroundAttemptForCurrentSession() async throws {
        let memoryStore = InMemoryPermissionStore()
        try await memoryStore.setDecision(
            for: externalKey(scheme: "mailto"),
            decision: externalDecision(.allow, persistence: .session, reason: "session-allow"),
            sessionOwnerId: "window-a"
        )
        let coordinator = SumiPermissionCoordinator(
            policyResolver: ExternalSchemeProceedPolicyResolver(),
            memoryStore: memoryStore,
            persistentStore: ExternalSchemeBridgePermissionStore(),
            sessionOwnerId: "window-a",
            now: { externalFixedDate }
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { externalFixedDate }
        )
        let mailURL = URL(string: "mailto:test@example.com")!

        let result = await bridge.evaluate(
            externalRequest(targetURL: mailURL, userActivation: .none),
            tabContext: externalTabContext()
        )

        XCTAssertTrue(result.didOpen)
        XCTAssertEqual(result.coordinatorDecision?.persistence, .session)
        XCTAssertEqual(resolver.openedURLs, [mailURL])
    }

    func testEphemeralProfileDoesNotReadOrWritePersistentExternalSchemeDecisions() async {
        let store = ExternalSchemeBridgePermissionStore()
        await store.seed(
            externalKey(scheme: "mailto", isEphemeralProfile: false),
            decision: externalDecision(.allow, persistence: .persistent, reason: "persistent-allow")
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = realExternalBridge(store: store, resolver: resolver)

        let result = await bridge.evaluate(
            externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .none),
            tabContext: externalTabContext(isEphemeralProfile: true)
        )

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.result, .blockedByDefault)
        XCTAssertTrue(resolver.openedURLs.isEmpty)
        let getCount = await store.getDecisionCallCount()
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(getCount, 0)
        XCTAssertEqual(setCount, 0)
    }

    func testUnsupportedSchemeNeverCallsOpenOrCoordinator() async {
        let store = ExternalSchemeBridgePermissionStore()
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: [])
        let bridge = realExternalBridge(store: store, resolver: resolver)

        let result = await bridge.evaluate(
            externalRequest(targetURL: URL(string: "unknown-scheme://payload")!, userActivation: .navigationAction),
            tabContext: externalTabContext()
        )

        XCTAssertEqual(result.record?.result, .unsupportedScheme)
        XCTAssertEqual(result.reason, "external-scheme-no-installed-handler")
        XCTAssertTrue(resolver.openedURLs.isEmpty)
        let getCount = await store.getDecisionCallCount()
        XCTAssertEqual(getCount, 0)
    }

    func testOpenFailureRecordsDeterministicFailure() async {
        let store = ExternalSchemeBridgePermissionStore()
        await store.seed(
            externalKey(scheme: "mailto"),
            decision: externalDecision(.allow, persistence: .persistent, reason: "stored-allow")
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        resolver.openResult = false
        let bridge = realExternalBridge(store: store, resolver: resolver)

        let result = await bridge.evaluate(
            externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .navigationAction),
            tabContext: externalTabContext()
        )

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.result, .openFailed)
        XCTAssertEqual(result.reason, "external-scheme-open-failed")
        XCTAssertEqual(resolver.openedURLs, [URL(string: "mailto:test@example.com")!])
    }

    func testInvalidOriginFailsClosedBeforeCoordinatorDecision() async {
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let coordinator = ExternalSchemeFakePermissionCoordinator(
            decision: externalCoordinatorDecision(.granted, reason: "should-not-be-used")
        )
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { externalFixedDate }
        )

        let result = await bridge.evaluate(
            externalRequest(
                targetURL: URL(string: "mailto:test@example.com")!,
                requestingOrigin: .invalid(reason: "missing-origin"),
                userActivation: .navigationAction
            ),
            tabContext: externalTabContext()
        )

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.result, .blockedByDefault)
        XCTAssertEqual(result.reason, "external-scheme-origin-not-keyable")
        XCTAssertTrue(resolver.openedURLs.isEmpty)
        let contexts = await coordinator.recordedContexts()
        XCTAssertTrue(contexts.isEmpty)
    }

    func testSecurityContextUsesTrustedOriginsProfileSurfaceAndActivation() {
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: ExternalSchemeFakePermissionCoordinator(
                decision: externalCoordinatorDecision(.promptRequired, reason: "ask")
            ),
            appResolver: ExternalSchemeFakeResolver(handlerSchemes: ["mailto"]),
            now: { externalFixedDate }
        )
        let context = bridge.securityContext(
            for: externalRequest(
                targetURL: URL(string: "mailto:test@example.com")!,
                userActivation: .none
            ),
            tabContext: externalTabContext(
                profilePartitionId: "Profile-A",
                isEphemeralProfile: true,
                committedURL: URL(string: "https://top.example/committed")!,
                visibleURL: URL(string: "https://visible.example/path")!,
                mainFrameURL: URL(string: "https://main.example/path")!,
                displayDomain: "spoofed.example"
            )
        )

        XCTAssertEqual(context.requestingOrigin.identity, "https://request.example")
        XCTAssertEqual(context.topOrigin.identity, "https://top.example")
        XCTAssertEqual(context.profilePartitionId, "profile-a")
        XCTAssertEqual(context.transientPageId, "tab-a:1")
        XCTAssertEqual(context.surface, .normalTab)
        XCTAssertTrue(context.isEphemeralProfile)
        XCTAssertEqual(context.committedURL, URL(string: "https://top.example/committed")!)
        XCTAssertEqual(context.visibleURL, URL(string: "https://visible.example/path")!)
        XCTAssertEqual(context.mainFrameURL, URL(string: "https://main.example/path")!)
        XCTAssertEqual(context.hasUserGesture, false)
        XCTAssertEqual(context.request.displayDomain, "spoofed.example")
        XCTAssertEqual(context.request.permissionTypes, [.externalScheme("mailto")])
    }

    func testDuplicateBackgroundAttemptsRecordOneSeriesAndAbuseHook() async {
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        var events: [SumiExternalSchemePermissionEvent] = []
        let bridge = realExternalBridge(
            store: ExternalSchemeBridgePermissionStore(),
            resolver: resolver
        ) { events.append($0) }
        let request = externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .none)

        _ = await bridge.evaluate(request, tabContext: externalTabContext())
        _ = await bridge.evaluate(request, tabContext: externalTabContext())

        let records = bridge.attempts(forPageId: "tab-a:1")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.attemptCount, 2)
        XCTAssertTrue(events.contains(.possibleAbuse(requestId: "external-a", pageId: "tab-a:1", attemptCount: 2)))
    }

    private func realExternalBridge(
        store: ExternalSchemeBridgePermissionStore,
        resolver: ExternalSchemeFakeResolver,
        eventSink: SumiExternalSchemePermissionBridge.EventSink? = nil
    ) -> SumiExternalSchemePermissionBridge {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: ExternalSchemeProceedPolicyResolver(),
            persistentStore: store,
            now: { externalFixedDate }
        )
        return SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { externalFixedDate },
            eventSink: eventSink
        )
    }
}

private extension SumiExternalSchemePermissionResult {
    var record: SumiExternalSchemeAttemptRecord? {
        switch action {
        case .opened(let record),
             .blocked(let record),
             .unsupported(let record),
             .openFailed(let record):
            return record
        }
    }
}

@MainActor
private final class ExternalSchemeFakeResolver: SumiExternalAppResolving {
    private let handlerSchemes: Set<String>
    private let appDisplayName: String?
    var openResult = true
    private(set) var appInfoURLs: [URL] = []
    private(set) var openedURLs: [URL] = []

    init(handlerSchemes: Set<String>, appDisplayName: String? = "External App") {
        self.handlerSchemes = Set(handlerSchemes.map(SumiPermissionType.normalizedExternalScheme))
        self.appDisplayName = appDisplayName
    }

    func appInfo(for url: URL) -> SumiExternalAppInfo? {
        appInfoURLs.append(url)
        let scheme = SumiExternalSchemePermissionRequest.normalizedScheme(for: url)
        guard handlerSchemes.contains(scheme) else { return nil }
        return SumiExternalAppInfo(
            normalizedScheme: scheme,
            appURL: URL(fileURLWithPath: "/Applications/\(scheme).app"),
            appDisplayName: appDisplayName
        )
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return openResult
    }
}

private actor ExternalSchemeFakePermissionCoordinator: SumiPermissionCoordinating {
    private let decision: SumiPermissionCoordinatorDecision
    private var contexts: [SumiPermissionSecurityContext] = []

    init(decision: SumiPermissionCoordinatorDecision) {
        self.decision = decision
    }

    func requestPermission(_ context: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        return decision
    }

    func queryPermissionState(_ context: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        return decision
    }

    func activeQuery(forPageId _: String) -> SumiPermissionAuthorizationQuery? {
        nil
    }

    func stateSnapshot() -> SumiPermissionCoordinatorState {
        SumiPermissionCoordinatorState()
    }

    func events() -> AsyncStream<SumiPermissionCoordinatorEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    @discardableResult
    func cancel(requestId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        externalCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancel(pageId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        externalCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancelNavigation(pageId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        externalCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancelTab(tabId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        externalCoordinatorDecision(.cancelled, reason: reason)
    }

    func recordedContexts() -> [SumiPermissionSecurityContext] {
        contexts
    }
}

private actor ExternalSchemeProceedPolicyResolver: SumiPermissionPolicyResolver {
    func evaluate(_: SumiPermissionSecurityContext) async -> SumiPermissionPolicyResult {
        .proceed(
            source: .defaultSetting,
            reason: SumiPermissionPolicyReason.allowed,
            systemAuthorizationSnapshot: nil,
            mayOpenSystemSettings: false,
            requiresSystemAuthorizationPrompt: false,
            allowedPersistences: [.oneTime, .session, .persistent]
        )
    }
}

private actor ExternalSchemeBridgePermissionStore: SumiPermissionStore {
    private var records: [String: SumiPermissionStoreRecord] = [:]
    private var getCount = 0
    private var setCount = 0

    func seed(_ key: SumiPermissionKey, decision: SumiPermissionDecision) {
        records[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord? {
        getCount += 1
        return records[key.persistentIdentity]
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

    func clearForDisplayDomains(_ displayDomains: Set<String>, profilePartitionId: String) async throws {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        let domains = Set(displayDomains.map(SumiPermissionStoreRecord.normalizedDisplayDomain))
        records = records.filter { _, record in
            record.key.profilePartitionId != profileId || !domains.contains(record.displayDomain)
        }
    }

    func clearForOrigins(_ origins: Set<SumiPermissionOrigin>, profilePartitionId: String) async throws {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        let identities = Set(origins.map(\.identity))
        records = records.filter { _, record in
            record.key.profilePartitionId != profileId
                || (!identities.contains(record.key.requestingOrigin.identity)
                    && !identities.contains(record.key.topOrigin.identity))
        }
    }

    @discardableResult
    func expireDecisions(now _: Date) async throws -> Int {
        0
    }

    func recordLastUsed(for _: SumiPermissionKey, at _: Date) async throws {}

    func getDecisionCallCount() -> Int {
        getCount
    }

    func setDecisionCallCount() -> Int {
        setCount
    }
}

private let externalRequestOrigin = SumiPermissionOrigin(string: "https://request.example")
private let externalTopOrigin = SumiPermissionOrigin(string: "https://top.example")
private let externalFixedDate = Date(timeIntervalSince1970: 1_800_000_000)

private func externalRequest(
    id: String = "external-a",
    targetURL: URL?,
    sourceURL: URL? = URL(string: "https://request.example/source"),
    requestingOrigin: SumiPermissionOrigin = externalRequestOrigin,
    userActivation: SumiExternalSchemeUserActivationState,
    classification: SumiExternalSchemeClassification? = nil,
    isRedirectChain: Bool = false,
    metadata: [String: String] = [:]
) -> SumiExternalSchemePermissionRequest {
    SumiExternalSchemePermissionRequest(
        id: id,
        path: .navigationResponder,
        targetURL: targetURL,
        sourceURL: sourceURL,
        requestingOrigin: requestingOrigin,
        userActivation: userActivation,
        classification: classification,
        isMainFrame: true,
        isRedirectChain: isRedirectChain,
        navigationActionMetadata: metadata
    )
}

private func externalTabContext(
    tabId: String = "tab-a",
    pageId: String = "tab-a:1",
    profilePartitionId: String = "profile-a",
    isEphemeralProfile: Bool = false,
    committedURL: URL? = URL(string: "https://top.example"),
    visibleURL: URL? = URL(string: "https://top.example/path"),
    mainFrameURL: URL? = URL(string: "https://top.example"),
    displayDomain: String? = nil
) -> SumiExternalSchemePermissionTabContext {
    SumiExternalSchemePermissionTabContext(
        tabId: tabId,
        pageId: pageId,
        profilePartitionId: profilePartitionId,
        isEphemeralProfile: isEphemeralProfile,
        committedURL: committedURL,
        visibleURL: visibleURL,
        mainFrameURL: mainFrameURL,
        isActiveTab: true,
        isVisibleTab: true,
        navigationOrPageGeneration: "1",
        displayDomain: displayDomain
    )
}

private func externalKey(
    requestingOrigin: SumiPermissionOrigin = externalRequestOrigin,
    topOrigin: SumiPermissionOrigin = externalTopOrigin,
    scheme: String,
    profilePartitionId: String = "profile-a",
    isEphemeralProfile: Bool = false
) -> SumiPermissionKey {
    SumiPermissionKey(
        requestingOrigin: requestingOrigin,
        topOrigin: topOrigin,
        permissionType: .externalScheme(scheme),
        profilePartitionId: profilePartitionId,
        transientPageId: "tab-a:1",
        isEphemeralProfile: isEphemeralProfile
    )
}

private func externalDecision(
    _ state: SumiPermissionState,
    persistence: SumiPermissionPersistence,
    source: SumiPermissionDecisionSource = .user,
    reason: String
) -> SumiPermissionDecision {
    SumiPermissionDecision(
        state: state,
        persistence: persistence,
        source: source,
        reason: reason,
        createdAt: externalFixedDate,
        updatedAt: externalFixedDate
    )
}

private func externalCoordinatorDecision(
    _ outcome: SumiPermissionCoordinatorOutcome,
    reason: String
) -> SumiPermissionCoordinatorDecision {
    let state: SumiPermissionState? = {
        switch outcome {
        case .granted:
            return .allow
        case .denied:
            return .deny
        case .promptRequired:
            return .ask
        default:
            return nil
        }
    }()
    return SumiPermissionCoordinatorDecision(
        outcome: outcome,
        state: state,
        persistence: outcome == .granted || outcome == .denied ? .persistent : nil,
        source: outcome == .granted || outcome == .denied ? .user : .defaultSetting,
        reason: reason,
        permissionTypes: [.externalScheme("mailto")],
        keys: [externalKey(scheme: "mailto")],
        shouldPersist: false
    )
}
