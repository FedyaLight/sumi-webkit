import XCTest

@testable import Sumi
import SumiDomain

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
                targetURL: URL(string: "sumi://history"),
                userActivation: .navigationAction,
                isRedirectChain: false
            ),
            .internalOrBrowserOwned
        )
        XCTAssertFalse(SumiExternalSchemePermissionRequest.isValidExternalSchemeURL(URL(string: "sumi://history")!))
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
        XCTAssertEqual(result.record?.redactedTargetURLString, "mailto:test@example.com")
        XCTAssertNotEqual(result.record?.redactedTargetURLString?.contains("secret"), true)
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
        XCTAssertEqual(result.record?.reason, "stored-persistent-deny")
        XCTAssertTrue(resolver.openedURLs.isEmpty)
    }

    func testStoredAllowOpensOneForegroundMainFrameCallbackWithoutUserActivation() async {
        let store = ExternalSchemeBridgePermissionStore()
        await store.seed(
            externalKey(scheme: "mailto"),
            decision: externalDecision(.allow, persistence: .persistent, reason: "stored-allow")
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = realExternalBridge(store: store, resolver: resolver)
        var willOpenCalled = false

        let firstResult = await bridge.evaluate(
            externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .none),
            tabContext: externalTabContext(),
            willOpen: { willOpenCalled = true }
        )
        let repeatedResult = await bridge.evaluate(
            externalRequest(
                id: "external-b",
                targetURL: URL(string: "mailto:test@example.com")!,
                userActivation: .none
            ),
            tabContext: externalTabContext()
        )
        let clickedResult = await bridge.evaluate(
            externalRequest(
                id: "external-c",
                targetURL: URL(string: "mailto:test@example.com")!,
                userActivation: .navigationAction
            ),
            tabContext: externalTabContext()
        )

        XCTAssertTrue(firstResult.didOpen)
        XCTAssertTrue(willOpenCalled)
        XCTAssertFalse(repeatedResult.didOpen)
        XCTAssertEqual(repeatedResult.record?.result, .blockedByDefault)
        XCTAssertEqual(repeatedResult.record?.reason, "external-scheme-automatic-attempt-already-used")
        XCTAssertTrue(clickedResult.didOpen)
        XCTAssertEqual(
            resolver.openedURLs,
            [
                URL(string: "mailto:test@example.com")!,
                URL(string: "mailto:test@example.com")!,
            ]
        )
    }

    func testUserActivatedNoDecisionBlocksPromptPresenterUnavailableWithoutPersistingDeny() async {
        let store = ExternalSchemeBridgePermissionStore()
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = realExternalBridge(store: store, resolver: resolver)

        let result = await bridge.evaluate(
            externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .navigationAction),
            tabContext: externalTabContext()
        )

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.result, .blockedPromptPresenterUnavailable)
        XCTAssertEqual(result.record?.reason, SumiExternalSchemePendingStrategy.promptPresenterUnavailableBlock.reason)
        XCTAssertTrue(resolver.openedURLs.isEmpty)
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
    }

    func testForegroundMainFrameNoDecisionDoesNotPersistDenyWhenPromptUIIsUnavailable() async {
        let store = ExternalSchemeBridgePermissionStore()
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = realExternalBridge(store: store, resolver: resolver)

        let result = await bridge.evaluate(
            externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .none),
            tabContext: externalTabContext()
        )

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.result, .blockedPromptPresenterUnavailable)
        XCTAssertEqual(result.record?.reason, SumiExternalSchemePendingStrategy.promptPresenterUnavailableBlock.reason)
        XCTAssertTrue(resolver.openedURLs.isEmpty)
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
    }

    func testActiveVisibleMainFrameOAuthCallbackPromptsAndOpensAfterGrant() async {
        let callbackURL = URL(string: "t3code://app/?ticket=secret")!
        let coordinator = ExternalSchemeQueryThenRequestCoordinator(
            queryDecision: externalCoordinatorDecision(
                .promptRequired,
                reason: "ask",
                scheme: "t3code"
            ),
            requestDecision: externalCoordinatorDecision(
                .granted,
                reason: "user-allow",
                scheme: "t3code"
            )
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["t3code"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { externalFixedDate }
        )

        let result = await bridge.evaluate(
            externalRequest(targetURL: callbackURL, userActivation: .none),
            tabContext: externalTabContext()
        )

        let requestCount = await coordinator.requestCount()
        XCTAssertTrue(result.didOpen)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(resolver.openedURLs, [callbackURL])
    }

    func testBackgroundSubframeCannotPromptOrOpenWithoutUserActivation() async {
        let coordinator = ExternalSchemeQueryThenRequestCoordinator(
            queryDecision: externalCoordinatorDecision(.promptRequired, reason: "ask"),
            requestDecision: externalCoordinatorDecision(.granted, reason: "should-not-be-used")
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { externalFixedDate }
        )

        let result = await bridge.evaluate(
            externalRequest(
                targetURL: URL(string: "mailto:test@example.com")!,
                userActivation: .none,
                isMainFrame: false
            ),
            tabContext: externalTabContext()
        )

        let requestCount = await coordinator.requestCount()
        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.reason, "external-scheme-background-default-block")
        XCTAssertEqual(requestCount, 0)
        XCTAssertTrue(resolver.openedURLs.isEmpty)
    }

    func testUserActivatedSubframeCannotReuseAllowOrOpen() async {
        let coordinator = ExternalSchemeFakePermissionCoordinator(
            decision: externalCoordinatorDecision(.granted, reason: "stored-allow")
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { externalFixedDate }
        )

        let result = await bridge.evaluate(
            externalRequest(
                targetURL: URL(string: "mailto:test@example.com")!,
                userActivation: .navigationAction,
                isMainFrame: false
            ),
            tabContext: externalTabContext()
        )

        let contexts = await coordinator.recordedContexts()
        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.reason, "external-scheme-background-default-block")
        XCTAssertTrue(contexts.isEmpty)
        XCTAssertTrue(resolver.openedURLs.isEmpty)
    }

    func testNonNormalSurfaceCannotPromptOrOpenWithoutUserActivation() async {
        let coordinator = ExternalSchemeQueryThenRequestCoordinator(
            queryDecision: externalCoordinatorDecision(.promptRequired, reason: "ask"),
            requestDecision: externalCoordinatorDecision(.granted, reason: "should-not-be-used")
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { externalFixedDate }
        )

        let result = await bridge.evaluate(
            externalRequest(
                targetURL: URL(string: "mailto:test@example.com")!,
                userActivation: .none
            ),
            tabContext: externalTabContext(surface: .glance)
        )

        let requestCount = await coordinator.requestCount()
        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.reason, "external-scheme-background-default-block")
        XCTAssertEqual(requestCount, 0)
        XCTAssertTrue(resolver.openedURLs.isEmpty)
    }

    func testUserActivatedNonNormalSurfaceCannotReuseAllowOrOpen() async {
        let coordinator = ExternalSchemeFakePermissionCoordinator(
            decision: externalCoordinatorDecision(.granted, reason: "stored-allow")
        )
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { externalFixedDate }
        )

        let result = await bridge.evaluate(
            externalRequest(
                targetURL: URL(string: "mailto:test@example.com")!,
                userActivation: .navigationAction
            ),
            tabContext: externalTabContext(surface: .glance)
        )

        let contexts = await coordinator.recordedContexts()
        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.reason, "external-scheme-background-default-block")
        XCTAssertTrue(contexts.isEmpty)
        XCTAssertTrue(resolver.openedURLs.isEmpty)
    }

    func testUnknownActivationCanPromptForForegroundMainFrameCallback() async {
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = realExternalBridge(store: ExternalSchemeBridgePermissionStore(), resolver: resolver)

        let result = await bridge.evaluate(
            externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .unknown),
            tabContext: externalTabContext()
        )

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.result, .blockedPromptPresenterUnavailable)
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
        XCTAssertEqual(otherScheme.record?.result, .blockedPromptPresenterUnavailable)
        XCTAssertEqual(otherSite.record?.result, .blockedPromptPresenterUnavailable)
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

        XCTAssertEqual(result.record?.result, .blockedPromptPresenterUnavailable)
        XCTAssertEqual(result.record?.reason, SumiExternalSchemePendingStrategy.promptPresenterUnavailableBlock.reason)
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
    }

    func testSessionAllowOpensForegroundMainFrameCallbackWithoutUserActivation() async throws {
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
        var willOpenCalled = false

        let result = await bridge.evaluate(
            externalRequest(targetURL: mailURL, userActivation: .none),
            tabContext: externalTabContext(),
            willOpen: { willOpenCalled = true }
        )

        XCTAssertTrue(result.didOpen)
        XCTAssertTrue(willOpenCalled)
        XCTAssertEqual(result.record?.result, .opened)
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
        XCTAssertEqual(result.record?.result, .blockedPromptPresenterUnavailable)
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
        XCTAssertEqual(result.record?.reason, "external-scheme-no-installed-handler")
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
        XCTAssertEqual(result.record?.reason, "external-scheme-open-failed")
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
        XCTAssertEqual(result.record?.reason, "external-scheme-origin-not-keyable")
        XCTAssertTrue(resolver.openedURLs.isEmpty)
        let contexts = await coordinator.recordedContexts()
        XCTAssertTrue(contexts.isEmpty)
    }

    func testSecurityContextUsesTrustedOriginsProfileSurfaceAndActivation() throws {
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
        XCTAssertFalse(try XCTUnwrap(context.hasUserGesture))
        XCTAssertEqual(context.request.displayDomain, "spoofed.example")
        XCTAssertEqual(context.request.permissionTypes, [.externalScheme("mailto")])
    }

    func testSecurityContextPropagatesGlanceSurfaceFromTabContext() {
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
            tabContext: externalTabContext(surface: .glance)
        )

        XCTAssertEqual(context.surface, .glance)
    }

    func testDuplicateAutomaticAttemptsAreRateLimited() async {
        let resolver = ExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        var events: [SumiExternalSchemePermissionEvent] = []
        let bridge = realExternalBridge(
            store: ExternalSchemeBridgePermissionStore(),
            resolver: resolver
        ) { events.append($0) }
        let request = externalRequest(targetURL: URL(string: "mailto:test@example.com")!, userActivation: .none)

        _ = await bridge.evaluate(request, tabContext: externalTabContext())
        _ = await bridge.evaluate(request, tabContext: externalTabContext())

        let records = bridge.sessionStore.records(forPageId: "tab-a:1")
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.last?.result, .blockedByDefault)
        XCTAssertEqual(records.last?.reason, "external-scheme-automatic-attempt-already-used")
        XCTAssertTrue(events.contains(
            .blockedByDefault(
                requestId: "external-a",
                pageId: "tab-a:1",
                reason: "external-scheme-automatic-attempt-already-used"
            )
        ))
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
            pendingStrategy: .promptPresenterUnavailableBlock,
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

private actor ExternalSchemeQueryThenRequestCoordinator: SumiPermissionCoordinating {
    private let queryDecision: SumiPermissionCoordinatorDecision
    private let requestDecision: SumiPermissionCoordinatorDecision
    private var requests = 0

    init(
        queryDecision: SumiPermissionCoordinatorDecision,
        requestDecision: SumiPermissionCoordinatorDecision
    ) {
        self.queryDecision = queryDecision
        self.requestDecision = requestDecision
    }

    func requestPermission(_: SumiPermissionSecurityContext) -> SumiPermissionCoordinatorDecision {
        requests += 1
        return requestDecision
    }

    func queryPermissionState(_: SumiPermissionSecurityContext) -> SumiPermissionCoordinatorDecision {
        queryDecision
    }

    func activeQuery(forPageId _: String) -> SumiPermissionAuthorizationQuery? { nil }
    func stateSnapshot() -> SumiPermissionCoordinatorState { SumiPermissionCoordinatorState() }
    func events() -> AsyncStream<SumiPermissionCoordinatorEvent> {
        AsyncStream { $0.finish() }
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

    func requestCount() -> Int { requests }
}

private actor ExternalSchemeProceedPolicyResolver: SumiPermissionPolicyResolver {
    func evaluate(_: SumiPermissionSecurityContext) async -> SumiPermissionPolicyResult {
        .proceed(
            source: .defaultSetting,
            reason: SumiPermissionPolicyReason.allowed,
            systemAuthorizationSnapshot: nil,
            mayOpenSystemSettings: false,
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

    func getDecision(for key: SumiPermissionKey) async -> SumiPermissionStoreRecord? {
        getCount += 1
        return records[key.persistentIdentity]
    }

    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async {
        setCount += 1
        records[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func resetDecision(for key: SumiPermissionKey) async {
        records.removeValue(forKey: key.persistentIdentity)
    }

    func listDecisions(profilePartitionId: String) async -> [SumiPermissionStoreRecord] {
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

    func clearAll(profilePartitionId: String) async {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        records = records.filter { _, record in record.key.profilePartitionId != profileId }
    }

    func clearForDisplayDomains(_ displayDomains: Set<String>, profilePartitionId: String) async {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        let domains = Set(displayDomains.map(SumiPermissionStoreRecord.normalizedDisplayDomain))
        records = records.filter { _, record in
            record.key.profilePartitionId != profileId || !domains.contains(record.displayDomain)
        }
    }

    func clearForOrigins(_ origins: Set<SumiPermissionOrigin>, profilePartitionId: String) async {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        let identities = Set(origins.map(\.identity))
        records = records.filter { _, record in
            record.key.profilePartitionId != profileId
                || (!identities.contains(record.key.requestingOrigin.identity)
                    && !identities.contains(record.key.topOrigin.identity))
        }
    }

    @discardableResult
    func expireDecisions(now _: Date) async -> Int {
        0
    }

    func recordLastUsed(for _: SumiPermissionKey, at _: Date) async { /* no-op */ }

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
    requestingOrigin: SumiPermissionOrigin = externalRequestOrigin,
    userActivation: SumiExternalSchemeUserActivationState,
    classification: SumiExternalSchemeClassification? = nil,
    isMainFrame: Bool = true,
    isRedirectChain: Bool = false
) -> SumiExternalSchemePermissionRequest {
    SumiExternalSchemePermissionRequest(
        id: id,
        targetURL: targetURL,
        requestingOrigin: requestingOrigin,
        userActivation: userActivation,
        classification: classification,
        isMainFrame: isMainFrame,
        isRedirectChain: isRedirectChain
    )
}

private func externalTabContext(
    tabId: String = "tab-a",
    pageId: String = "tab-a:1",
    surface: SumiPermissionSecurityContext.Surface = .normalTab,
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
        surface: surface,
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
    reason: String,
    scheme: String = "mailto"
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
        permissionTypes: [.externalScheme(scheme)],
        keys: [externalKey(scheme: scheme)]
    )
}
