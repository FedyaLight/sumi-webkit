import XCTest

@testable import Sumi

@MainActor
final class SumiPopupPermissionBridgeTests: XCTestCase {
    func testPopupClassificationCoversActivationBackgroundEmptyAndInternalCases() {
        XCTAssertEqual(
            SumiPopupPermissionRequest.classify(
                targetURL: URL(string: "https://popup.example"),
                sourceURL: URL(string: "https://top.example"),
                requestingOrigin: popupOrigin,
                userActivation: .directWebKit
            ),
            .directUserActivated
        )
        XCTAssertEqual(
            SumiPopupPermissionRequest.classify(
                targetURL: URL(string: "https://popup.example"),
                sourceURL: URL(string: "https://top.example"),
                requestingOrigin: popupOrigin,
                userActivation: .recentBrowserEvent(kind: "mouseDown", eventTimestamp: 10, currentTime: 12)
            ),
            .shortWindowUserActivated
        )
        XCTAssertEqual(
            SumiPopupPermissionRequest.classify(
                targetURL: URL(string: "https://popup.example"),
                sourceURL: URL(string: "https://top.example"),
                requestingOrigin: popupOrigin,
                userActivation: .unknown
            ),
            .scriptOrBackground
        )
        XCTAssertEqual(
            SumiPopupPermissionRequest.classify(
                targetURL: URL(string: "about:blank"),
                sourceURL: URL(string: "https://top.example"),
                requestingOrigin: popupOrigin,
                userActivation: .directWebKit
            ),
            .emptyOrAboutBlank
        )
        XCTAssertEqual(
            SumiPopupPermissionRequest.classify(
                targetURL: URL(string: "sumi://settings"),
                sourceURL: URL(string: "https://top.example"),
                requestingOrigin: popupOrigin,
                userActivation: .directWebKit
            ),
            .internalOrBrowserOwned
        )
    }

    func testUserActivatedPopupWithNoStoredDecisionAllowsByDefaultWithoutWritingStore() async {
        let store = PopupBridgePermissionStore()
        let bridge = realCoordinatorBridge(store: store)

        let result = await bridge.evaluate(
            popupRequest(userActivation: .directWebKit),
            tabContext: tabContext()
        )

        XCTAssertTrue(result.isAllowed)
        XCTAssertEqual(result.coordinatorDecision?.outcome, .granted)
        XCTAssertEqual(result.reason, "popup-user-activation-default-allow")
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
        XCTAssertTrue(bridge.blockedPopups(forPageId: "tab-a:1").isEmpty)
    }

    func testBackgroundPopupWithNoStoredDecisionBlocksAndRecordsWithoutPersistingDeny() async {
        let store = PopupBridgePermissionStore()
        let blockedStore = SumiBlockedPopupStore()
        var events: [SumiPopupPermissionEvent] = []
        let bridge = realCoordinatorBridge(store: store, blockedPopupStore: blockedStore) {
            events.append($0)
        }

        let result = await bridge.evaluate(
            popupRequest(userActivation: .none),
            tabContext: tabContext()
        )

        XCTAssertFalse(result.isAllowed)
        XCTAssertEqual(result.coordinatorDecision?.outcome, .denied)
        XCTAssertEqual(result.reason, SumiPopupPendingStrategy.blockUntilPromptUIExists.reason)
        XCTAssertEqual(blockedStore.records(forPageId: "tab-a:1").count, 1)
        XCTAssertEqual(blockedStore.records(forPageId: "tab-a:1").first?.reason, .blockedByPromptUIUnavailable)
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
        XCTAssertTrue(events.contains(.attempted(requestId: "popup-a", pageId: "tab-a:1", classification: .scriptOrBackground)))
        XCTAssertTrue(events.contains(.blockedByDefault(
            requestId: "popup-a",
            pageId: "tab-a:1",
            reason: SumiPopupPendingStrategy.blockUntilPromptUIExists.reason
        )))
    }

    func testUnknownActivationIsConservativeAndBlockedByDefault() async {
        let bridge = realCoordinatorBridge(store: PopupBridgePermissionStore())

        let result = await bridge.evaluate(
            popupRequest(id: "unknown", userActivation: .unknown),
            tabContext: tabContext()
        )

        XCTAssertFalse(result.isAllowed)
        XCTAssertEqual(bridge.blockedPopups(forPageId: "tab-a:1").first?.id, "unknown")
    }

    func testPersistentDenyBlocksUserActivatedPopupAndPersistentAllowOpensBackgroundPopup() async {
        let denyStore = PopupBridgePermissionStore()
        await denyStore.seed(popupKey(), decision: popupDecision(.deny, persistence: .persistent, reason: "stored-deny"))
        let denyBridge = realCoordinatorBridge(store: denyStore)

        let denied = await denyBridge.evaluate(
            popupRequest(userActivation: .directWebKit),
            tabContext: tabContext()
        )

        XCTAssertFalse(denied.isAllowed)
        XCTAssertEqual(denied.coordinatorDecision?.outcome, .denied)
        XCTAssertEqual(denyBridge.blockedPopups(forPageId: "tab-a:1").first?.reason, .blockedByStoredDeny)

        let allowStore = PopupBridgePermissionStore()
        await allowStore.seed(popupKey(), decision: popupDecision(.allow, persistence: .persistent, reason: "stored-allow"))
        let allowBridge = realCoordinatorBridge(store: allowStore)

        let allowed = await allowBridge.evaluate(
            popupRequest(id: "background-allowed", userActivation: .none),
            tabContext: tabContext()
        )

        XCTAssertTrue(allowed.isAllowed)
        XCTAssertEqual(allowed.coordinatorDecision?.outcome, .granted)
        XCTAssertTrue(allowBridge.blockedPopups(forPageId: "tab-a:1").isEmpty)
    }

    func testSessionAllowOpensBackgroundPopupForCurrentSession() async throws {
        let memoryStore = InMemoryPermissionStore()
        try await memoryStore.setDecision(
            for: popupKey(),
            decision: popupDecision(.allow, persistence: .session, reason: "session-allow"),
            sessionOwnerId: "window-a"
        )
        let coordinator = SumiPermissionCoordinator(
            policyResolver: PopupProceedPolicyResolver(),
            memoryStore: memoryStore,
            persistentStore: PopupBridgePermissionStore(),
            sessionOwnerId: "window-a",
            now: { popupFixedDate }
        )
        let bridge = SumiPopupPermissionBridge(coordinator: coordinator, now: { popupFixedDate })

        let result = await bridge.evaluate(
            popupRequest(userActivation: .none),
            tabContext: tabContext()
        )

        XCTAssertTrue(result.isAllowed)
        XCTAssertEqual(result.coordinatorDecision?.persistence, .session)
    }

    func testEphemeralProfileDoesNotReadOrWritePersistentPopupDecisions() async {
        let store = PopupBridgePermissionStore()
        await store.seed(
            popupKey(isEphemeralProfile: false),
            decision: popupDecision(.allow, persistence: .persistent, reason: "persistent-allow")
        )
        let bridge = realCoordinatorBridge(store: store)

        let result = await bridge.evaluate(
            popupRequest(userActivation: .none),
            tabContext: tabContext(isEphemeralProfile: true)
        )

        XCTAssertFalse(result.isAllowed)
        let getCount = await store.getDecisionCallCount()
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(getCount, 0)
        XCTAssertEqual(setCount, 0)
    }

    func testPromptRequiredUsesPopupDefaultPolicyInsteadOfUnconditionalPrompt() async {
        let userActivatedBridge = SumiPopupPermissionBridge(
            coordinator: PopupFakePermissionCoordinator(decision: popupCoordinatorDecision(.promptRequired, reason: "ask")),
            now: { popupFixedDate }
        )

        let userActivated = await userActivatedBridge.evaluate(
            popupRequest(userActivation: .navigationAction),
            tabContext: tabContext()
        )

        XCTAssertTrue(userActivated.isAllowed)
        XCTAssertTrue(userActivatedBridge.blockedPopups(forPageId: "tab-a:1").isEmpty)

        let backgroundBridge = SumiPopupPermissionBridge(
            coordinator: PopupFakePermissionCoordinator(decision: popupCoordinatorDecision(.promptRequired, reason: "ask")),
            now: { popupFixedDate }
        )
        let background = await backgroundBridge.evaluate(
            popupRequest(id: "background", userActivation: .none),
            tabContext: tabContext()
        )

        XCTAssertFalse(background.isAllowed)
        XCTAssertEqual(background.reason, SumiPopupPendingStrategy.blockUntilPromptUIExists.reason)
        XCTAssertEqual(backgroundBridge.blockedPopups(forPageId: "tab-a:1").first?.reason, .blockedByPromptUIUnavailable)
    }

    func testSecurityContextUsesTrustedOriginsProfileAndNormalTabSurface() {
        let bridge = SumiPopupPermissionBridge(
            coordinator: PopupFakePermissionCoordinator(decision: popupCoordinatorDecision(.promptRequired, reason: "ask")),
            now: { popupFixedDate }
        )
        let context = bridge.securityContext(
            for: popupRequest(requestingOrigin: popupOrigin, userActivation: .directWebKit),
            tabContext: tabContext(
                profilePartitionId: "Profile-A",
                isEphemeralProfile: true,
                committedURL: URL(string: "https://top.example/path")!,
                visibleURL: URL(string: "https://visible.example/path")!,
                displayDomain: "spoofed.example"
            )
        )

        XCTAssertEqual(context.requestingOrigin.identity, "https://popup.example")
        XCTAssertEqual(context.topOrigin.identity, "https://top.example")
        XCTAssertEqual(context.profilePartitionId, "profile-a")
        XCTAssertEqual(context.transientPageId, "tab-a:1")
        XCTAssertEqual(context.surface, .normalTab)
        XCTAssertTrue(context.isEphemeralProfile)
        XCTAssertEqual(context.request.displayDomain, "spoofed.example")
    }

    func testInvalidOrMissingTrustedOriginFailsClosedAndRecordsBlockedState() async {
        let bridge = SumiPopupPermissionBridge(
            coordinator: PopupFakePermissionCoordinator(decision: popupCoordinatorDecision(.granted, reason: "unused")),
            now: { popupFixedDate }
        )

        let result = await bridge.evaluate(
            popupRequest(requestingOrigin: .invalid(reason: "missing-origin"), userActivation: .directWebKit),
            tabContext: tabContext()
        )

        XCTAssertFalse(result.isAllowed)
        XCTAssertEqual(result.reason, "popup-origin-not-keyable")
        XCTAssertEqual(bridge.blockedPopups(forPageId: "tab-a:1").first?.reason, .blockedByInvalidOrigin)
    }

    func testBrowserOwnedExtensionPopupIsExplicitAndSumiInternalPopupIsBlocked() async {
        let coordinator = PopupFakePermissionCoordinator(decision: popupCoordinatorDecision(.promptRequired, reason: "unused"))
        let bridge = SumiPopupPermissionBridge(coordinator: coordinator, now: { popupFixedDate })

        let extensionAllowed = await bridge.evaluate(
            popupRequest(
                id: "extension-popup",
                targetURL: URL(string: "webkit-extension://abc/page.html"),
                sourceURL: URL(string: "webkit-extension://abc/source.html"),
                requestingOrigin: .invalid(reason: "extension-origin"),
                userActivation: .none,
                classification: .internalOrBrowserOwned,
                metadata: ["isExtensionOriginated": "true"]
            ),
            tabContext: tabContext()
        )
        XCTAssertTrue(extensionAllowed.isAllowed)

        let sumiBlocked = await bridge.evaluate(
            popupRequest(
                id: "sumi-popup",
                targetURL: URL(string: "sumi://settings"),
                sourceURL: URL(string: "https://top.example"),
                userActivation: .directWebKit,
                classification: .internalOrBrowserOwned
            ),
            tabContext: tabContext()
        )
        XCTAssertFalse(sumiBlocked.isAllowed)
        XCTAssertEqual(bridge.blockedPopups(forPageId: "tab-a:1").first { $0.id == "sumi-popup" }?.reason, .blockedByPolicy)
    }

    func testAboutBlankAndEmptyPopupsAreNotReopenableWhenBlocked() async {
        let bridge = realCoordinatorBridge(store: PopupBridgePermissionStore())

        let blank = await bridge.evaluate(
            popupRequest(id: "blank", targetURL: URL(string: "about:blank"), userActivation: .none),
            tabContext: tabContext()
        )
        let empty = await bridge.evaluate(
            popupRequest(id: "empty", targetURL: nil, userActivation: .none),
            tabContext: tabContext()
        )

        XCTAssertFalse(blank.isAllowed)
        XCTAssertFalse(empty.isAllowed)
        XCTAssertEqual(bridge.blockedPopups(forPageId: "tab-a:1").first { $0.id == "blank" }?.canOpenLater, false)
        XCTAssertEqual(bridge.blockedPopups(forPageId: "tab-a:1").first { $0.id == "empty" }?.canOpenLater, false)
    }

    func testDuplicateBackgroundProcessingRecordsOneBlockedPopupAttemptSeries() async {
        let bridge = realCoordinatorBridge(store: PopupBridgePermissionStore())
        let request = popupRequest(userActivation: .none)

        _ = await bridge.evaluate(request, tabContext: tabContext())
        _ = await bridge.evaluate(request, tabContext: tabContext())

        let records = bridge.blockedPopups(forPageId: "tab-a:1")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.attemptCount, 2)
    }

    func testOpenBlockedPopupBackendOnlyOpensSafeKnownURLAfterExplicitCall() async {
        let bridge = realCoordinatorBridge(store: PopupBridgePermissionStore())
        _ = await bridge.evaluate(
            popupRequest(id: "blocked", targetURL: URL(string: "https://popup.example/window"), userActivation: .none),
            tabContext: tabContext()
        )
        var openedURLs: [URL] = []

        let opened = bridge.openBlockedPopup(id: "blocked", pageId: "tab-a:1") { url in
            openedURLs.append(url)
        }

        XCTAssertTrue(opened)
        XCTAssertEqual(openedURLs, [URL(string: "https://popup.example/window")!])
    }

    func testSourceLevelIntegrationRoutesBothPopupPathsThroughBridge() throws {
        let uiDelegateSource = try sourceFile("Sumi/Models/Tab/Tab+UIDelegate.swift")
        let popupResponderSource = try sourceFile("Sumi/Models/Tab/Navigation/SumiPopupHandlingNavigationResponder.swift")

        XCTAssertTrue(uiDelegateSource.contains("popupHandling.createWebViewAsync("))
        XCTAssertTrue(uiDelegateSource.contains("completionHandler(popupWebView)"))
        XCTAssertTrue(popupResponderSource.contains("popupPermissionBridge.evaluate("))
        XCTAssertTrue(popupResponderSource.contains("evaluateSynchronouslyForWebKitFallback("))
        XCTAssertTrue(popupResponderSource.contains("guard permissionResult.isAllowed else { return nil }"))
        XCTAssertTrue(popupResponderSource.contains("return .cancel"))
        XCTAssertTrue(popupResponderSource.contains("createChildWebView("))
    }

    private func realCoordinatorBridge(
        store: PopupBridgePermissionStore,
        blockedPopupStore: SumiBlockedPopupStore? = nil,
        eventSink: SumiPopupPermissionBridge.EventSink? = nil
    ) -> SumiPopupPermissionBridge {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: PopupProceedPolicyResolver(),
            persistentStore: store,
            now: { popupFixedDate }
        )
        return SumiPopupPermissionBridge(
            coordinator: coordinator,
            blockedPopupStore: blockedPopupStore,
            now: { popupFixedDate },
            eventSink: eventSink
        )
    }

    private func popupRequest(
        id: String = "popup-a",
        targetURL: URL? = URL(string: "https://popup.example/window"),
        sourceURL: URL? = URL(string: "https://top.example/source"),
        requestingOrigin: SumiPermissionOrigin = popupOrigin,
        userActivation: SumiPopupUserActivationState,
        classification: SumiPopupClassification? = nil,
        metadata: [String: String] = [:]
    ) -> SumiPopupPermissionRequest {
        SumiPopupPermissionRequest(
            id: id,
            path: .uiDelegateCreateWebView,
            targetURL: targetURL,
            sourceURL: sourceURL,
            requestingOrigin: requestingOrigin,
            userActivation: userActivation,
            classification: classification,
            isMainFrame: true,
            navigationActionMetadata: metadata
        )
    }

    private func tabContext(
        tabId: String = "tab-a",
        pageId: String = "tab-a:1",
        profilePartitionId: String = "profile-a",
        isEphemeralProfile: Bool = false,
        committedURL: URL? = URL(string: "https://top.example"),
        visibleURL: URL? = URL(string: "https://top.example/path"),
        mainFrameURL: URL? = URL(string: "https://top.example"),
        displayDomain: String? = nil
    ) -> SumiPopupPermissionTabContext {
        SumiPopupPermissionTabContext(
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

    private func sourceFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

private actor PopupFakePermissionCoordinator: SumiPermissionCoordinating {
    private let decision: SumiPermissionCoordinatorDecision
    private(set) var contexts: [SumiPermissionSecurityContext] = []

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
        popupCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancel(pageId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        popupCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancelNavigation(pageId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        popupCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancelTab(tabId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        popupCoordinatorDecision(.cancelled, reason: reason)
    }
}

private actor PopupProceedPolicyResolver: SumiPermissionPolicyResolver {
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

private actor PopupBridgePermissionStore: SumiPermissionStore {
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
        let domains = Set(displayDomains.map(SumiPermissionStoreRecord.normalizedDisplayDomain))
        records = records.filter { _, record in
            record.key.profilePartitionId != profilePartitionId || !domains.contains(record.displayDomain)
        }
    }

    func clearForOrigins(_ origins: Set<SumiPermissionOrigin>, profilePartitionId: String) async throws {
        let identities = Set(origins.map(\.identity))
        records = records.filter { _, record in
            record.key.profilePartitionId != profilePartitionId
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

private let popupOrigin = SumiPermissionOrigin(string: "https://popup.example")
private let popupFixedDate = Date(timeIntervalSince1970: 1_800_000_000)

private func popupKey(isEphemeralProfile: Bool = false) -> SumiPermissionKey {
    SumiPermissionKey(
        requestingOrigin: popupOrigin,
        topOrigin: SumiPermissionOrigin(string: "https://top.example"),
        permissionType: .popups,
        profilePartitionId: "profile-a",
        transientPageId: "tab-a:1",
        isEphemeralProfile: isEphemeralProfile
    )
}

private func popupDecision(
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
        createdAt: popupFixedDate,
        updatedAt: popupFixedDate
    )
}

private func popupCoordinatorDecision(
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
        permissionTypes: [.popups],
        keys: [popupKey()],
        shouldPersist: false
    )
}
