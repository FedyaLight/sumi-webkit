import WebKit
import XCTest

@testable import Sumi
import SumiDomain

private let promptBridgeFixedDate = Date(timeIntervalSince1970: 1_800_000_400)

@available(macOS 13.0, *)
@MainActor
final class SumiPermissionPromptBridgeIntegrationTests: XCTestCase {
    func testPopoverDismissalSettlesActiveQueryAndReleasesSidebarPin() async {
        let store = PromptBridgePermissionStore()
        let coordinator = makeCoordinator(
            systemStates: [.camera: .authorized],
            store: store
        )
        let presenter = SumiPermissionPromptPresenter()
        let tab = permissionPromptTab()
        let windowState = BrowserWindowState()
        presenter.configure(
            coordinator: coordinator,
            systemPermissionService: FakeSumiSystemPermissionService(
                states: [.camera: .authorized]
            )
        )
        presenter.update(tab: tab, windowState: windowState)

        let request = Task {
            await coordinator.requestPermission(
                presenterContext(tab: tab, permissionType: .camera, id: "camera-dismissed")
            )
        }
        let query = await waitForActiveQuery(
            coordinator,
            pageId: tab.currentPermissionPageId()
        )
        let presenterDisplayedQuery = await waitForPresenter(
            presenter,
            queryId: query.id
        )
        XCTAssertTrue(presenterDisplayedQuery)
        XCTAssertTrue(
            windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(
                for: windowState.id
            )
        )

        presenter.isPresented = false
        presenter.handlePresentationChange(isPresented: false)

        let decision = await request.value
        XCTAssertEqual(decision.outcome, .dismissed)
        let activeQuery = await coordinator.activeQuery(
            forPageId: tab.currentPermissionPageId()
        )
        let storedDecisions = await store.listDecisions(profilePartitionId: "profile-a")
        XCTAssertNil(activeQuery)
        XCTAssertTrue(storedDecisions.isEmpty)
        XCTAssertFalse(
            windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(
                for: windowState.id
            )
        )
    }

    func testPresenterAdvancesFromCameraToMicrophone() async {
        let coordinator = makeCoordinator(
            systemStates: [.camera: .authorized, .microphone: .authorized],
            store: PromptBridgePermissionStore()
        )
        let presenter = SumiPermissionPromptPresenter()
        let tab = permissionPromptTab()
        let windowState = BrowserWindowState()
        presenter.configure(
            coordinator: coordinator,
            systemPermissionService: FakeSumiSystemPermissionService(
                states: [.camera: .authorized, .microphone: .authorized]
            )
        )
        presenter.update(tab: tab, windowState: windowState)

        let cameraRequest = Task {
            await coordinator.requestPermission(
                presenterContext(tab: tab, permissionType: .camera, id: "camera-first")
            )
        }
        let cameraQuery = await waitForActiveQuery(
            coordinator,
            pageId: tab.currentPermissionPageId()
        )
        let presenterDisplayedCamera = await waitForPresenter(
            presenter,
            queryId: cameraQuery.id
        )
        XCTAssertTrue(presenterDisplayedCamera)

        let microphoneRequest = Task {
            await coordinator.requestPermission(
                presenterContext(tab: tab, permissionType: .microphone, id: "microphone-second")
            )
        }
        let queuedMicrophone = await waitForQueuedQuery(
            coordinator,
            pageId: tab.currentPermissionPageId()
        )
        XCTAssertTrue(queuedMicrophone)

        await presenter.viewModel?.performAction(.allowThisTime)
        let cameraDecision = await cameraRequest.value
        XCTAssertEqual(cameraDecision.outcome, .granted)
        let microphoneQuery = await waitForDifferentActiveQuery(
            coordinator,
            pageId: tab.currentPermissionPageId(),
            excluding: cameraQuery.id
        )
        let presenterDisplayedMicrophone = await waitForPresenter(
            presenter,
            queryId: microphoneQuery.id
        )
        XCTAssertTrue(presenterDisplayedMicrophone)
        XCTAssertTrue(presenter.isPresented)
        XCTAssertEqual(presenter.viewModel?.permissionTypes, [.microphone])

        await presenter.viewModel?.performAction(.dismiss)
        let microphoneDecision = await microphoneRequest.value
        XCTAssertEqual(microphoneDecision.outcome, .dismissed)
    }

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
        withExtendedLifetime(webView) { /* no-op */ }
    }

    func testMediaBackgroundPromptFailsClosedWithoutWaitingForPresenter() async {
        let coordinator = makeCoordinator(
            systemStates: [.camera: .authorized],
            store: PromptBridgePermissionStore()
        )
        let bridge = SumiWebKitPermissionBridge(
            coordinator: coordinator,
            runtimeController: FakeSumiRuntimePermissionController(),
            now: { promptBridgeFixedDate }
        )
        let expectation = XCTestExpectation(description: "media auto prompt decision")
        var decisions: [WKPermissionDecision] = []
        let webView = WKWebView()

        bridge.handleMediaCaptureAuthorization(
            mediaRequest(permissionTypes: [.camera]),
            tabContext: mediaTabContext(isActiveTab: false, isVisibleTab: false),
            webView: webView
        ) { decision in
            decisions.append(decision)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(decisions, [.deny])
        let activeQuery = await coordinator.activeQuery(forPageId: "tab-a:1")
        XCTAssertNil(activeQuery)
        withExtendedLifetime(webView) { /* no-op */ }
    }

    func testGeolocationBackgroundPromptFailsClosedWithoutWaitingForPresenter() async {
        let coordinator = makeCoordinator(
            systemStates: [.geolocation: .authorized],
            store: PromptBridgePermissionStore()
        )
        let provider = FakeSumiGeolocationProvider()
        let bridge = SumiWebKitGeolocationBridge(
            coordinator: coordinator,
            geolocationProvider: provider,
            now: { promptBridgeFixedDate }
        )
        let expectation = XCTestExpectation(description: "geolocation auto prompt decision")
        var decisions: [WKPermissionDecision] = []
        let webView = WKWebView()

        bridge.handleGeolocationAuthorization(
            SumiWebKitGeolocationRequest(
                id: "geo-a",
                requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
                isMainFrame: true
            ),
            tabContext: geolocationTabContext(isActiveTab: false, isVisibleTab: false),
            webView: webView
        ) { decision in
            decisions.append(decision)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(decisions, [.deny])
        let activeQuery = await coordinator.activeQuery(forPageId: "tab-a:1")
        XCTAssertNil(activeQuery)
        withExtendedLifetime(webView) { /* no-op */ }
        withExtendedLifetime(provider) { /* no-op */ }
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

    func testNotificationBackgroundPromptResolvesDefaultWithoutWaitingForPresenter() async {
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
                tabContext: notificationTabContext(isActiveTab: false, isVisibleTab: false)
            )
        }

        let result = await task.value
        XCTAssertEqual(result, .default)
        let activeQuery = await coordinator.activeQuery(forPageId: "tab-a:1")
        XCTAssertNil(activeQuery)
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
        withExtendedLifetime(webView) { /* no-op */ }
    }

    func testExternalForegroundMainFrameCallbackWaitsAndOpensOnlyAfterAllow() async {
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
                externalRequest(targetURL: targetURL, userActivation: .none),
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

    func testExternalBackgroundSubframeNoDecisionBlocksWithoutPrompt() async {
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
                userActivation: .none,
                isMainFrame: false
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
        await sumiPermissionIntegrationWaitForActiveQuery(
            coordinator,
            pageId: pageId,
            file: file,
            line: line
        )
    }

    private func waitForDifferentActiveQuery(
        _ coordinator: SumiPermissionCoordinator,
        pageId: String,
        excluding queryId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> SumiPermissionAuthorizationQuery {
        for _ in 0..<200 {
            if let query = await coordinator.activeQuery(forPageId: pageId),
               query.id != queryId {
                return query
            }
            await Task.yield()
        }
        XCTFail("Permission queue did not promote the next query", file: file, line: line)
        fatalError("Permission queue did not promote the next query")
    }

    private func waitForQueuedQuery(
        _ coordinator: SumiPermissionCoordinator,
        pageId: String
    ) async -> Bool {
        for _ in 0..<200 {
            if await coordinator.stateSnapshot().queueCountByPageId[pageId] == 1 {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func waitForPresenter(
        _ presenter: SumiPermissionPromptPresenter,
        queryId: String
    ) async -> Bool {
        for _ in 0..<200 {
            if presenter.isPresented, presenter.viewModel?.queryId == queryId {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func permissionPromptTab() -> Tab {
        Tab(
            url: URL(string: "https://example.com/page")!,
            name: "Permission prompt",
            loadsCachedFaviconOnInit: false
        )
    }

    private func presenterContext(
        tab: Tab,
        permissionType: SumiPermissionType,
        id: String
    ) -> SumiPermissionSecurityContext {
        sumiPermissionIntegrationContext(
            [permissionType],
            id: id,
            tabId: tab.id.uuidString.lowercased(),
            pageId: tab.currentPermissionPageId()
        )
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

    private func mediaTabContext(
        isActiveTab: Bool = true,
        isVisibleTab: Bool = true
    ) -> SumiWebKitMediaCaptureTabContext {
        SumiWebKitMediaCaptureTabContext(
            tabId: "tab-a",
            pageId: "tab-a:1",
            surface: .normalTab,
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            committedURL: URL(string: "https://example.com"),
            visibleURL: URL(string: "https://example.com/path"),
            mainFrameURL: URL(string: "https://example.com"),
            isActiveTab: isActiveTab,
            isVisibleTab: isVisibleTab,
            navigationOrPageGeneration: "1"
        )
    }

    private func geolocationTabContext(
        isActiveTab: Bool = true,
        isVisibleTab: Bool = true
    ) -> SumiWebKitGeolocationTabContext {
        SumiWebKitGeolocationTabContext(
            tabId: "tab-a",
            pageId: "tab-a:1",
            surface: .normalTab,
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            committedURL: URL(string: "https://example.com"),
            visibleURL: URL(string: "https://example.com/path"),
            mainFrameURL: URL(string: "https://example.com"),
            isActiveTab: isActiveTab,
            isVisibleTab: isVisibleTab,
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

    private func notificationTabContext(
        isActiveTab: Bool = true,
        isVisibleTab: Bool = true
    ) -> SumiWebNotificationTabContext {
        SumiWebNotificationTabContext(
            tabId: "tab-a",
            pageId: "tab-a:1",
            surface: .normalTab,
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            committedURL: URL(string: "https://example.com/page"),
            visibleURL: URL(string: "https://example.com/page"),
            mainFrameURL: URL(string: "https://example.com/page"),
            isActiveTab: isActiveTab,
            isVisibleTab: isVisibleTab,
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
            surface: .normalTab,
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
        userActivation: SumiExternalSchemeUserActivationState,
        isMainFrame: Bool = true
    ) -> SumiExternalSchemePermissionRequest {
        SumiExternalSchemePermissionRequest(
            id: "external-a",
            targetURL: targetURL,
            requestingOrigin: SumiPermissionOrigin(string: "https://request.example"),
            userActivation: userActivation,
            isMainFrame: isMainFrame,
            isRedirectChain: false
        )
    }

    private func externalTabContext() -> SumiExternalSchemePermissionTabContext {
        SumiExternalSchemePermissionTabContext(
            tabId: "tab-a",
            pageId: "tab-a:1",
            surface: .normalTab,
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

    func getDecision(for key: SumiPermissionKey) async -> SumiPermissionStoreRecord? {
        records[key.persistentIdentity]
    }

    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async {
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

    func clearForDisplayDomains(
        _ displayDomains: Set<String>,
        profilePartitionId _: String
    ) async {
        let domains = Set(displayDomains.map(SumiPermissionStoreRecord.normalizedDisplayDomain))
        records = records.filter { _, record in !domains.contains(record.displayDomain) }
    }

    func clearForOrigins(
        _ origins: Set<SumiPermissionOrigin>,
        profilePartitionId _: String
    ) async {
        let identities = Set(origins.map(\.identity))
        records = records.filter { _, record in
            !identities.contains(record.key.requestingOrigin.identity)
                && !identities.contains(record.key.topOrigin.identity)
        }
    }

    @discardableResult
    func expireDecisions(now _: Date) async -> Int {
        0
    }

    func recordLastUsed(for _: SumiPermissionKey, at _: Date) async { /* no-op */ }
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
