import WebKit
import XCTest

@testable import Sumi

private let promptBridgeFixedDate = Date(timeIntervalSince1970: 1_800_000_400)

@available(macOS 13.0, *)
@MainActor
final class SumiPermissionPromptBridgeIntegrationTests: XCTestCase {
    func testMediaPromptRequiredWaitsForUserSettlementAndGrants() async {
        let coordinator = makeCoordinator(
            systemStates: [.camera: .authorized],
            store: PromptBridgePermissionStore()
        )
        let bridge = SumiWebKitPermissionBridge(
            coordinator: coordinator,
            runtimeController: FakeSumiRuntimePermissionController(),
            now: { promptBridgeFixedDate }
        )
        let expectation = XCTestExpectation(description: "media decision")
        var decisions: [WKPermissionDecision] = []
        let webView = WKWebView()

        bridge.handleMediaCaptureAuthorization(
            mediaRequest(permissionTypes: [.camera]),
            tabContext: mediaTabContext(),
            webView: webView
        ) { decision in
            decisions.append(decision)
            expectation.fulfill()
        }

        let query = await waitForActiveQuery(coordinator, pageId: "tab-a:1")
        XCTAssertTrue(decisions.isEmpty)
        await coordinator.approveOnce(query.id)

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(decisions, [.grant])
        withExtendedLifetime(webView) {}
    }

    func testNotificationDismissResolvesWebsiteRequestToDefault() async {
        let coordinator = makeCoordinator(
            systemStates: [.notifications: .authorized],
            store: PromptBridgePermissionStore()
        )
        let bridge = SumiNotificationPermissionBridge(
            coordinator: coordinator,
            notificationService: FakeSumiNotificationService(),
            now: { promptBridgeFixedDate }
        )

        let task = Task {
            await bridge.requestWebsitePermission(
                request: notificationRequest(),
                tabContext: notificationTabContext()
            )
        }
        let query = await waitForActiveQuery(coordinator, pageId: "tab-a:1")
        await coordinator.dismiss(query.id)

        let result = await task.value
        XCTAssertEqual(result, .default)
    }

    func testStorageAccessPromptRequiredWaitsForUserSettlementAndDeniesOnDismiss() async {
        let coordinator = makeCoordinator(store: PromptBridgePermissionStore())
        let bridge = SumiStorageAccessPermissionBridge(
            coordinator: coordinator,
            now: { promptBridgeFixedDate }
        )
        let expectation = XCTestExpectation(description: "storage access completion")
        let webView = WKWebView()
        var results: [Bool] = []

        bridge.handleStorageAccessRequest(
            storageRequest(),
            tabContext: storageTabContext(),
            webView: webView
        ) { granted in
            results.append(granted)
            expectation.fulfill()
        }

        let query = await waitForActiveQuery(coordinator, pageId: "tab-a:1")
        await coordinator.dismiss(query.id)

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(results, [false])
        withExtendedLifetime(webView) {}
    }

    func testExternalUserActivatedNoDecisionWaitsAndOpensOnlyAfterAllow() async {
        let store = PromptBridgePermissionStore()
        let coordinator = makeCoordinator(store: store)
        let resolver = PromptExternalResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { promptBridgeFixedDate }
        )
        let targetURL = URL(string: "mailto:test@example.com")!

        let task = Task {
            await bridge.evaluate(
                externalRequest(targetURL: targetURL, userActivation: .navigationAction),
                tabContext: externalTabContext()
            )
        }
        let query = await waitForActiveQuery(coordinator, pageId: "tab-a:1")
        XCTAssertTrue(resolver.openedURLs.isEmpty)
        await coordinator.approveOnce(query.id)

        let result = await task.value
        XCTAssertTrue(result.didOpen)
        XCTAssertEqual(resolver.openedURLs, [targetURL])
    }

    func testExternalBackgroundNoDecisionBlocksWithoutPrompt() async {
        let coordinator = makeCoordinator(store: PromptBridgePermissionStore())
        let resolver = PromptExternalResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { promptBridgeFixedDate }
        )

        let result = await bridge.evaluate(
            externalRequest(
                targetURL: URL(string: "mailto:test@example.com")!,
                userActivation: .none
            ),
            tabContext: externalTabContext()
        )

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.record?.result, .blockedByDefault)
        let activeQuery = await coordinator.activeQuery(forPageId: "tab-a:1")
        XCTAssertNil(activeQuery)
    }

    private func makeCoordinator(
        systemStates: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState] = [:],
        store: PromptBridgePermissionStore
    ) -> SumiPermissionCoordinator {
        SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: FakeSumiSystemPermissionService(states: systemStates)
            ),
            persistentStore: store,
            now: { promptBridgeFixedDate }
        )
    }

    private func waitForActiveQuery(
        _ coordinator: SumiPermissionCoordinator,
        pageId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> SumiPermissionAuthorizationQuery {
        for _ in 0..<100 {
            if let query = await coordinator.activeQuery(forPageId: pageId) {
                return query
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for active permission query", file: file, line: line)
        fatalError("Timed out waiting for active permission query")
    }

    private func mediaRequest(
        permissionTypes: [SumiPermissionType]
    ) -> SumiWebKitMediaCaptureRequest {
        SumiWebKitMediaCaptureRequest(
            id: "request-a",
            permissionTypes: permissionTypes,
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            isMainFrame: true
        )
    }

    private func mediaTabContext() -> SumiWebKitMediaCaptureTabContext {
        SumiWebKitMediaCaptureTabContext(
            tabId: "tab-a",
            pageId: "tab-a:1",
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            committedURL: URL(string: "https://example.com"),
            visibleURL: URL(string: "https://example.com/path"),
            mainFrameURL: URL(string: "https://example.com"),
            isActiveTab: true,
            isVisibleTab: true,
            navigationOrPageGeneration: "1"
        )
    }

    private func notificationRequest() -> SumiWebNotificationRequest {
        SumiWebNotificationRequest(
            id: "notification-a",
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            isMainFrame: true
        )
    }

    private func notificationTabContext() -> SumiWebNotificationTabContext {
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

    private func storageRequest() -> SumiStorageAccessRequest {
        SumiStorageAccessRequest(
            id: "storage-a",
            requestingDomain: "idp.example",
            currentDomain: "rp.example"
        )
    }

    private func storageTabContext() -> SumiStorageAccessTabContext {
        SumiStorageAccessTabContext(
            tabId: "tab-a",
            pageId: "tab-a:1",
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            committedURL: URL(string: "https://rp.example"),
            visibleURL: URL(string: "https://rp.example/path"),
            mainFrameURL: URL(string: "https://rp.example"),
            isActiveTab: true,
            isVisibleTab: true,
            navigationOrPageGeneration: "1"
        )
    }

    private func externalRequest(
        targetURL: URL,
        userActivation: SumiExternalSchemeUserActivationState
    ) -> SumiExternalSchemePermissionRequest {
        SumiExternalSchemePermissionRequest(
            id: "external-a",
            targetURL: targetURL,
            requestingOrigin: SumiPermissionOrigin(string: "https://request.example"),
            userActivation: userActivation,
            isMainFrame: true,
            isRedirectChain: false
        )
    }

    private func externalTabContext() -> SumiExternalSchemePermissionTabContext {
        SumiExternalSchemePermissionTabContext(
            tabId: "tab-a",
            pageId: "tab-a:1",
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            committedURL: URL(string: "https://request.example/page"),
            visibleURL: URL(string: "https://request.example/page"),
            mainFrameURL: URL(string: "https://request.example/page"),
            isActiveTab: true,
            isVisibleTab: true,
            navigationOrPageGeneration: "1",
            displayDomain: "request.example"
        )
    }
}

private actor PromptBridgePermissionStore: SumiPermissionStore {
    private var records: [String: SumiPermissionStoreRecord] = [:]

    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord? {
        records[key.persistentIdentity]
    }

    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async throws {
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
private final class PromptExternalResolver: SumiExternalAppResolving {
    private let handlerSchemes: Set<String>
    private(set) var openedURLs: [URL] = []

    init(handlerSchemes: Set<String>) {
        self.handlerSchemes = Set(handlerSchemes.map(SumiPermissionType.normalizedExternalScheme))
    }

    func appInfo(for url: URL) -> SumiExternalAppInfo? {
        let scheme = SumiExternalSchemePermissionRequest.normalizedScheme(for: url)
        guard handlerSchemes.contains(scheme) else { return nil }
        return SumiExternalAppInfo(
            appDisplayName: "External App"
        )
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }
}
