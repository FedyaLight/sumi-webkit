import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiStorageAccessPermissionBridgeTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_200)

    func testSecurityContextPreservesRequestingAndTopOrigins() {
        let bridge = makeBridge(store: StorageAccessBridgePermissionStore())
        let context = bridge.securityContext(
            for: storageRequest(requestingDomain: "IdP.Example."),
            tabContext: tabContext(
                profilePartitionId: "Profile-A",
                isEphemeralProfile: true,
                committedURL: URL(string: "https://rp.example:8443/page")!,
                visibleURL: URL(string: "https://rp.example:8443/page")!
            )
        )

        XCTAssertEqual(context.surface, .normalTab)
        XCTAssertEqual(context.requestingOrigin.identity, "https://idp.example")
        XCTAssertEqual(context.topOrigin.identity, "https://rp.example:8443")
        XCTAssertEqual(context.profilePartitionId, "profile-a")
        XCTAssertTrue(context.isEphemeralProfile)
        XCTAssertEqual(context.transientPageId, "tab-a:1")
        XCTAssertEqual(context.request.displayDomain, "idp.example")
        XCTAssertNil(context.hasUserGesture)
    }

    func testStoredAllowGrantsWebKitStorageAccess() async {
        let store = StorageAccessBridgePermissionStore()
        await store.seed(
            storageKey(),
            decision: storageDecision(.allow, reason: "stored-allow")
        )
        let bridge = makeBridge(store: store)

        let results = await resolve(bridge: bridge)

        XCTAssertEqual(results, [true])
    }

    func testStoredDenyDeniesWebKitStorageAccess() async {
        let store = StorageAccessBridgePermissionStore()
        await store.seed(
            storageKey(),
            decision: storageDecision(.deny, reason: "stored-deny")
        )
        let bridge = makeBridge(store: store)

        let results = await resolve(bridge: bridge)

        XCTAssertEqual(results, [false])
    }

    func testNoDecisionUsesTemporaryDenyAndDoesNotPersist() async {
        let store = StorageAccessBridgePermissionStore()
        let bridge = makeBridge(store: store)

        let results = await resolve(bridge: bridge)

        XCTAssertEqual(results, [false])
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
    }

    func testStoredAskUsesTemporaryDenyAndDoesNotPersistSiteDeny() async {
        let store = StorageAccessBridgePermissionStore()
        await store.seed(
            storageKey(),
            decision: storageDecision(.ask, reason: "stored-ask")
        )
        let bridge = makeBridge(store: store)

        let results = await resolve(bridge: bridge)

        XCTAssertEqual(results, [false])
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
        let storedState = await store.state(for: storageKey())
        XCTAssertEqual(storedState, .ask)
    }

    func testEphemeralProfileDoesNotReadOrWritePersistentDecision() async {
        let store = StorageAccessBridgePermissionStore()
        await store.seed(
            storageKey(isEphemeralProfile: false),
            decision: storageDecision(.allow, reason: "persistent-allow")
        )
        let bridge = makeBridge(store: store)

        let results = await resolve(
            bridge: bridge,
            tabContext: tabContext(isEphemeralProfile: true)
        )

        XCTAssertEqual(results, [false])
        let getCount = await store.getDecisionCallCount()
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(getCount, 0)
        XCTAssertEqual(setCount, 0)
    }

    func testMissingTrustedRequestingOriginDeniesWithoutStoreLookup() async {
        let store = StorageAccessBridgePermissionStore()
        let bridge = makeBridge(store: store)

        let results = await resolve(
            bridge: bridge,
            request: storageRequest(requestingDomain: "")
        )

        XCTAssertEqual(results, [false])
        let getCount = await store.getDecisionCallCount()
        XCTAssertEqual(getCount, 0)
    }

    func testInsecureTopOriginDeniesWithoutStoreLookup() async {
        let store = StorageAccessBridgePermissionStore()
        let bridge = makeBridge(store: store)

        let results = await resolve(
            bridge: bridge,
            tabContext: tabContext(
                committedURL: URL(string: "http://rp.example")!,
                visibleURL: URL(string: "http://rp.example")!,
                mainFrameURL: URL(string: "http://rp.example")!
            )
        )

        XCTAssertEqual(results, [false])
        let getCount = await store.getDecisionCallCount()
        XCTAssertEqual(getCount, 0)
    }

    func testSameOriginRequestFailsClosed() async {
        let store = StorageAccessBridgePermissionStore()
        let bridge = makeBridge(store: store)

        let results = await resolve(
            bridge: bridge,
            request: storageRequest(requestingDomain: "rp.example")
        )

        XCTAssertEqual(results, [false])
        let getCount = await store.getDecisionCallCount()
        XCTAssertEqual(getCount, 0)
    }

    func testUnavailableWebViewFailsClosedOnce() async {
        let store = StorageAccessBridgePermissionStore()
        let bridge = makeBridge(store: store)
        let expectation = XCTestExpectation(description: "Storage access completion")
        var results: [Bool] = []

        bridge.handleStorageAccessRequest(
            storageRequest(),
            tabContext: tabContext(),
            webView: nil
        ) { granted in
            results.append(granted)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(results, [false])
    }

    func testCompletionHandlerResolvesExactlyOnce() {
        var results: [Bool] = []
        let once = SumiStorageAccessCompletionHandler { results.append($0) }

        once.resolve(true)
        once.resolve(false)

        XCTAssertEqual(results, [true])
    }

    func testNormalTabUIDelegateRegistersPrivateStorageAccessSelectors() throws {
        let source = try sourceFile("Sumi/Models/Tab/Tab+UIDelegate.swift")

        XCTAssertTrue(source.contains("_webView:requestStorageAccessPanelForDomain:underCurrentDomain:completionHandler:"))
        XCTAssertTrue(source.contains("_webView:requestStorageAccessPanelForDomain:underCurrentDomain:forQuirkDomains:completionHandler:"))
        XCTAssertTrue(source.contains("storageAccessPermissionBridge.handleStorageAccessRequest("))
        XCTAssertFalse(source.contains("NSAlert.storageAccessAlert"))
    }

    private func makeBridge(
        store: StorageAccessBridgePermissionStore,
        pendingStrategy: SumiStorageAccessPendingStrategy = .promptPresenterUnavailableDeny
    ) -> SumiStorageAccessPermissionBridge {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: FakeSumiSystemPermissionService()
            ),
            persistentStore: store,
            now: { self.fixedDate }
        )
        return SumiStorageAccessPermissionBridge(
            coordinator: coordinator,
            pendingStrategy: pendingStrategy,
            pendingPollIntervalNanoseconds: 1_000_000,
            coordinatorTimeoutNanoseconds: 100_000_000,
            now: { self.fixedDate }
        )
    }

    private func resolve(
        bridge: SumiStorageAccessPermissionBridge,
        request: SumiStorageAccessRequest? = nil,
        tabContext: SumiStorageAccessTabContext? = nil
    ) async -> [Bool] {
        let expectation = XCTestExpectation(description: "Storage access result")
        let webView = WKWebView()
        var results: [Bool] = []
        bridge.handleStorageAccessRequest(
            request ?? storageRequest(),
            tabContext: tabContext ?? self.tabContext(),
            webView: webView
        ) { granted in
            results.append(granted)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)
        withExtendedLifetime(webView) {}
        return results
    }

    private func storageRequest(
        requestingDomain: String = "idp.example",
        currentDomain: String = "rp.example",
        quirkDomains: [String] = []
    ) -> SumiStorageAccessRequest {
        SumiStorageAccessRequest(
            id: "storage-access-a",
            requestingDomain: requestingDomain,
            currentDomain: currentDomain,
            quirkDomains: quirkDomains
        )
    }

    private func tabContext(
        tabId: String = "tab-a",
        pageId: String = "tab-a:1",
        profilePartitionId: String = "profile-a",
        isEphemeralProfile: Bool = false,
        committedURL: URL? = URL(string: "https://rp.example"),
        visibleURL: URL? = URL(string: "https://rp.example/path"),
        mainFrameURL: URL? = URL(string: "https://rp.example"),
        isActiveTab: Bool = true,
        isVisibleTab: Bool = true,
        navigationOrPageGeneration: String? = "1"
    ) -> SumiStorageAccessTabContext {
        SumiStorageAccessTabContext(
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

    private func storageKey(
        requestingOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://idp.example"),
        topOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://rp.example"),
        profilePartitionId: String = "profile-a",
        isEphemeralProfile: Bool = false
    ) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            permissionType: .storageAccess,
            profilePartitionId: profilePartitionId,
            transientPageId: "tab-a:1",
            isEphemeralProfile: isEphemeralProfile
        )
    }

    private func storageDecision(
        _ state: SumiPermissionState,
        persistence: SumiPermissionPersistence = .persistent,
        reason: String
    ) -> SumiPermissionDecision {
        SumiPermissionDecision(
            state: state,
            persistence: persistence,
            source: .user,
            reason: reason,
            createdAt: fixedDate,
            updatedAt: fixedDate
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

private actor StorageAccessBridgePermissionStore: SumiPermissionStore {
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

    func getDecisionCallCount() -> Int {
        getCount
    }

    func setDecisionCallCount() -> Int {
        setCount
    }

    func state(for key: SumiPermissionKey) -> SumiPermissionState? {
        records[key.persistentIdentity]?.decision.state
    }
}
