import WebKit
import XCTest

@testable import Sumi

@available(macOS 13.0, *)
@MainActor
final class SumiPermissionEndToEndFlowTests: XCTestCase {
    func testCameraFirstTimeAllowThisTimeBridgePromptAndPageLifecycle() async {
        let harness = makeHarness()
        let bridge = SumiWebKitPermissionBridge(
            coordinator: harness.coordinator,
            runtimeController: harness.runtimeController,
            now: sumiPermissionIntegrationDate
        )
        let webView = WKWebView()

        let firstDecisionTask = bridgeDecision(
            bridge: bridge,
            request: mediaRequest(id: "camera-first", permissionTypes: [.camera]),
            tabContext: mediaTabContext(pageId: "tab-a:1"),
            webView: webView
        )
        let firstQuery = await sumiPermissionIntegrationWaitForActiveQuery(harness.coordinator)
        XCTAssertEqual(firstQuery.permissionTypes, [.camera])

        let prompt = SumiPermissionPromptViewModel(
            query: firstQuery,
            coordinator: harness.coordinator,
            systemPermissionService: harness.systemService
        )
        await prompt.performAction(.allowThisTime)
        let firstDecision = await firstDecisionTask.value

        let setDecisionCallCount = await harness.store.setDecisionCallCount()
        XCTAssertEqual(firstDecision, [.grant])
        XCTAssertEqual(setDecisionCallCount, 0)

        let repeatedDecision = await bridgeDecision(
            bridge: bridge,
            request: mediaRequest(id: "camera-repeat", permissionTypes: [.camera]),
            tabContext: mediaTabContext(pageId: "tab-a:1"),
            webView: webView
        ).value
        XCTAssertEqual(repeatedDecision, [.grant])
        let repeatedActiveQuery = await harness.coordinator.activeQuery(forPageId: "tab-a:1")
        XCTAssertNil(repeatedActiveQuery)

        let reloadDecisionTask = bridgeDecision(
            bridge: bridge,
            request: mediaRequest(id: "camera-after-reload", permissionTypes: [.camera]),
            tabContext: mediaTabContext(pageId: "tab-a:2", generation: "2"),
            webView: webView
        )
        let reloadQuery = await sumiPermissionIntegrationWaitForActiveQuery(
            harness.coordinator,
            pageId: "tab-a:2"
        )
        XCTAssertEqual(reloadQuery.permissionTypes, [.camera])
        await harness.coordinator.cancel(queryId: reloadQuery.id, reason: "test-cleanup")
        let reloadDecision = await reloadDecisionTask.value
        XCTAssertEqual(reloadDecision, [.deny])
    }

    func testMicrophoneAllowWhileVisitingPersistsAndSettingsCanListIt() async throws {
        let harness = makeHarness()
        let bridge = SumiWebKitPermissionBridge(
            coordinator: harness.coordinator,
            runtimeController: harness.runtimeController,
            now: sumiPermissionIntegrationDate
        )
        let webView = WKWebView()

        let decisionTask = bridgeDecision(
            bridge: bridge,
            request: mediaRequest(id: "microphone-first", permissionTypes: [.microphone]),
            tabContext: mediaTabContext(),
            webView: webView
        )
        let query = await sumiPermissionIntegrationWaitForActiveQuery(harness.coordinator)
        let prompt = SumiPermissionPromptViewModel(
            query: query,
            coordinator: harness.coordinator,
            systemPermissionService: harness.systemService
        )
        await prompt.performAction(.allowWhileVisiting)

        let firstDecision = await decisionTask.value
        let microphoneKey = sumiPermissionIntegrationKey(.microphone)
        let microphoneRecord = await harness.store.record(for: microphoneKey)
        XCTAssertEqual(firstDecision, [.grant])
        XCTAssertEqual(microphoneRecord?.decision.state, .allow)
        XCTAssertEqual(microphoneRecord?.decision.persistence, .persistent)

        let futureDecision = await bridgeDecision(
            bridge: bridge,
            request: mediaRequest(id: "microphone-repeat", permissionTypes: [.microphone]),
            tabContext: mediaTabContext(),
            webView: webView
        ).value
        XCTAssertEqual(futureDecision, [.grant])

        let repository = makeSettingsRepository(coordinator: harness.coordinator)
        let rows = try await repository.siteRows(
            profile: SumiPermissionSettingsProfileContext(
                profilePartitionId: "profile-a",
                isEphemeralProfile: false,
                profileName: "Work"
            )
        )
        XCTAssertEqual(rows.map(\.scope.requestingOrigin.identity), ["https://example.com"])
        let detail = try await repository.siteDetail(
            scope: try XCTUnwrap(rows.first?.scope),
            profile: SumiPermissionSettingsProfileContext(
                profilePartitionId: "profile-a",
                isEphemeralProfile: false,
                profileName: "Work"
            ),
            profileObject: nil,
            includeDataSummary: false
        )
        XCTAssertEqual(
            detail.permissionRows.first { $0.kind == .sitePermission(.microphone) }?.currentOption,
            .allow
        )
    }

    func testGroupedCameraMicrophoneUsesOnePromptAndExpandsPersistentSettlement() async {
        let harness = makeHarness()
        let bridge = SumiWebKitPermissionBridge(
            coordinator: harness.coordinator,
            runtimeController: harness.runtimeController,
            now: sumiPermissionIntegrationDate
        )
        let webView = WKWebView()

        let decisionTask = bridgeDecision(
            bridge: bridge,
            request: mediaRequest(id: "grouped-media", permissionTypes: [.camera, .microphone]),
            tabContext: mediaTabContext(),
            webView: webView
        )
        let query = await sumiPermissionIntegrationWaitForActiveQuery(harness.coordinator)

        XCTAssertEqual(query.permissionTypes, [.camera, .microphone])
        XCTAssertEqual(query.presentationPermissionType, .cameraAndMicrophone)

        let prompt = SumiPermissionPromptViewModel(
            query: query,
            coordinator: harness.coordinator,
            systemPermissionService: harness.systemService
        )
        XCTAssertEqual(prompt.permissionType, .cameraAndMicrophone)
        await prompt.performAction(.allowWhileVisiting)

        let decision = await decisionTask.value
        let records = await harness.store.allRecords()
        let setDecisionCallCount = await harness.store.setDecisionCallCount()
        XCTAssertEqual(decision, [.grant])
        XCTAssertEqual(Set(records.map { $0.key.permissionType.identity }), Set(["camera", "microphone"]))
        XCTAssertFalse(records.contains { $0.key.permissionType == .cameraAndMicrophone })
        XCTAssertEqual(setDecisionCallCount, 2)
    }

    func testGeolocationGrantRegistersProviderAndNavigationClearsProviderAndOneTimeGrant() async {
        let harness = makeHarness()
        let provider = FakeSumiGeolocationProvider()
        let bridge = SumiWebKitGeolocationBridge(
            coordinator: harness.coordinator,
            geolocationProvider: provider,
            now: sumiPermissionIntegrationDate
        )
        let lifecycle = SumiPermissionGrantLifecycleController(
            coordinator: harness.coordinator,
            geolocationProvider: provider,
            filePickerBridge: nil,
            indicatorEventStore: SumiPermissionIndicatorEventStore(),
            blockedPopupStore: SumiBlockedPopupStore(),
            externalSchemeSessionStore: SumiExternalSchemeSessionStore()
        )
        let webView = WKWebView()

        let decisionTask = geolocationDecision(
            bridge: bridge,
            request: SumiWebKitGeolocationRequest(
                id: "geo-first",
                requestingOrigin: sumiPermissionIntegrationOrigin(),
                frameURL: URL(string: "https://example.com/page"),
                isMainFrame: true
            ),
            tabContext: geolocationTabContext(pageId: "tab-a:1"),
            webView: webView
        )
        let query = await sumiPermissionIntegrationWaitForActiveQuery(harness.coordinator)
        let prompt = SumiPermissionPromptViewModel(
            query: query,
            coordinator: harness.coordinator,
            systemPermissionService: harness.systemService
        )
        await prompt.performAction(.allowThisTime)

        let decision = await decisionTask.value
        XCTAssertEqual(decision, [.grant])
        XCTAssertTrue(provider.containsAllowedRequest(pageId: "tab-a:1"))

        let repeated = await harness.coordinator.queryPermissionState(
            sumiPermissionIntegrationContext([.geolocation], id: "geo-repeat", pageId: "tab-a:1")
        )
        XCTAssertEqual(repeated.outcome, .granted)

        lifecycle.handle(
            .mainFrameNavigation(
                pageId: "tab-a:1",
                tabId: "tab-a",
                profilePartitionId: "profile-a",
                targetURL: URL(string: "https://example.com/reloaded"),
                reason: "test-navigation"
            )
        )

        XCTAssertFalse(provider.containsAllowedRequest(pageId: "tab-a:1"))
        let afterNavigation = await harness.coordinator.queryPermissionState(
            sumiPermissionIntegrationContext([.geolocation], id: "geo-after-navigation", pageId: "tab-a:1")
        )
        XCTAssertEqual(afterNavigation.outcome, .promptRequired)
    }

    func testStorageAccessAllowAndDenyResolveCallbacksOnceWithTopOriginPartitioning() async {
        let allowHarness = makeHarness()
        let allowBridge = SumiStorageAccessPermissionBridge(
            coordinator: allowHarness.coordinator,
            now: sumiPermissionIntegrationDate
        )
        let webView = WKWebView()

        let allowTask = storageDecision(
            bridge: allowBridge,
            request: storageAccessRequest(id: "storage-allow"),
            tabContext: storageAccessTabContext(),
            webView: webView
        )
        let allowQuery = await sumiPermissionIntegrationWaitForActiveQuery(allowHarness.coordinator)
        XCTAssertEqual(allowQuery.permissionTypes, [.storageAccess])
        XCTAssertEqual(allowQuery.requestingOrigin.identity, "https://idp.example")
        XCTAssertEqual(allowQuery.topOrigin.identity, "https://rp.example")

        let allowPrompt = SumiPermissionPromptViewModel(
            query: allowQuery,
            coordinator: allowHarness.coordinator,
            systemPermissionService: allowHarness.systemService
        )
        await allowPrompt.performAction(.allow)

        let allowResult = await allowTask.value
        XCTAssertEqual(allowResult, [true])
        let storedAllow = await allowHarness.store.record(
            for: sumiPermissionIntegrationKey(
                .storageAccess,
                requestingOrigin: SumiPermissionOrigin(string: "https://idp.example"),
                topOrigin: SumiPermissionOrigin(string: "https://rp.example")
            )
        )
        XCTAssertEqual(storedAllow?.decision.state, .allow)
        XCTAssertEqual(storedAllow?.key.requestingOrigin.identity, "https://idp.example")
        XCTAssertEqual(storedAllow?.key.topOrigin.identity, "https://rp.example")

        let denyHarness = makeHarness()
        let denyBridge = SumiStorageAccessPermissionBridge(
            coordinator: denyHarness.coordinator,
            now: sumiPermissionIntegrationDate
        )
        let denyTask = storageDecision(
            bridge: denyBridge,
            request: storageAccessRequest(id: "storage-deny"),
            tabContext: storageAccessTabContext(),
            webView: webView
        )
        let denyQuery = await sumiPermissionIntegrationWaitForActiveQuery(denyHarness.coordinator)
        let denyPrompt = SumiPermissionPromptViewModel(
            query: denyQuery,
            coordinator: denyHarness.coordinator,
            systemPermissionService: denyHarness.systemService
        )
        await denyPrompt.performAction(.dontAllow)

        let denyResult = await denyTask.value
        let denySetDecisionCallCount = await denyHarness.store.setDecisionCallCount()
        XCTAssertEqual(denyResult, [false])
        XCTAssertEqual(denySetDecisionCallCount, 1)
    }

    func testExternalSchemeUserActivatedPromptCurrentAttemptPersistentAllowAndBackgroundBlock() async {
        let harness = makeHarness()
        let resolver = SumiPermissionIntegrationExternalAppResolver()
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: harness.coordinator,
            appResolver: resolver,
            now: sumiPermissionIntegrationDate
        )
        let tabContext = externalSchemeTabContext()

        let openThisTimeTask = Task { @MainActor in
            await bridge.evaluate(
                externalSchemeRequest(
                    id: "external-open-once",
                    userActivation: .navigationAction
                ),
                tabContext: tabContext
            )
        }
        let openThisTimeQuery = await sumiPermissionIntegrationWaitForActiveQuery(harness.coordinator)
        XCTAssertEqual(openThisTimeQuery.permissionTypes, [.externalScheme("mailto")])
        let openPrompt = SumiPermissionPromptViewModel(
            query: openThisTimeQuery,
            coordinator: harness.coordinator,
            systemPermissionService: harness.systemService,
            externalAppResolver: resolver
        )
        await openPrompt.performAction(.openThisTime)

        let openThisTime = await openThisTimeTask.value
        let openThisTimeSetDecisionCallCount = await harness.store.setDecisionCallCount()
        XCTAssertTrue(openThisTime.didOpen)
        XCTAssertEqual(resolver.openedURLs.map(\.absoluteString), ["mailto:test@example.com"])
        XCTAssertEqual(openThisTimeSetDecisionCallCount, 0)

        let alwaysAllowTask = Task { @MainActor in
            await bridge.evaluate(
                externalSchemeRequest(
                    id: "external-always",
                    userActivation: .navigationAction
                ),
                tabContext: tabContext
            )
        }
        let alwaysAllowQuery = await sumiPermissionIntegrationWaitForActiveQuery(harness.coordinator)
        let alwaysPrompt = SumiPermissionPromptViewModel(
            query: alwaysAllowQuery,
            coordinator: harness.coordinator,
            systemPermissionService: harness.systemService,
            externalAppResolver: resolver
        )
        await alwaysPrompt.performAction(.alwaysAllowExternal)

        let alwaysAllow = await alwaysAllowTask.value
        let storedExternalState = await harness.store.record(
            for: sumiPermissionIntegrationKey(.externalScheme("mailto"))
        )?.decision.state
        XCTAssertTrue(alwaysAllow.didOpen)
        XCTAssertEqual(
            storedExternalState,
            .allow
        )

        let allowedBackground = await bridge.evaluate(
            externalSchemeRequest(id: "external-background-allowed", userActivation: .none),
            tabContext: tabContext
        )
        XCTAssertTrue(allowedBackground.didOpen)
        XCTAssertEqual(resolver.openedURLs.count, 3)

        let blockedHarness = makeHarness()
        let blockedResolver = SumiPermissionIntegrationExternalAppResolver()
        let blockedBridge = SumiExternalSchemePermissionBridge(
            coordinator: blockedHarness.coordinator,
            appResolver: blockedResolver,
            now: sumiPermissionIntegrationDate
        )
        let blockedBackground = await blockedBridge.evaluate(
            externalSchemeRequest(id: "external-background-blocked", userActivation: .none),
            tabContext: tabContext
        )
        XCTAssertFalse(blockedBackground.didOpen)
        XCTAssertTrue(blockedResolver.openedURLs.isEmpty)
        let blockedActiveQuery = await blockedHarness.coordinator.activeQuery(forPageId: "tab-a:1")
        XCTAssertNil(blockedActiveQuery)
    }

    func testPopupDefaultsBackgroundSessionEventAndStoredAllow() async {
        let harness = makeHarness()
        let blockedPopupStore = SumiBlockedPopupStore()
        let bridge = SumiPopupPermissionBridge(
            coordinator: harness.coordinator,
            blockedPopupStore: blockedPopupStore,
            now: sumiPermissionIntegrationDate
        )
        let tabContext = popupTabContext()

        let userActivated = await bridge.evaluate(
            popupRequest(id: "popup-user-activated", userActivation: .directWebKit),
            tabContext: tabContext
        )
        XCTAssertTrue(userActivated.isAllowed)
        XCTAssertTrue(blockedPopupStore.records(forPageId: "tab-a:1").isEmpty)

        let background = await bridge.evaluate(
            popupRequest(id: "popup-background", userActivation: .none),
            tabContext: tabContext
        )
        XCTAssertFalse(background.isAllowed)
        let blockedRecords = blockedPopupStore.records(forPageId: "tab-a:1")
        XCTAssertEqual(blockedRecords.count, 1)
        XCTAssertEqual(blockedRecords.first?.id, "popup-background")
        XCTAssertEqual(blockedRecords.first?.reason, .blockedByPromptUIUnavailable)

        await harness.store.seed(
            sumiPermissionIntegrationKey(.popups),
            decision: sumiPermissionIntegrationDecision(.allow)
        )
        let storedAllow = await bridge.evaluate(
            popupRequest(id: "popup-background-stored-allow", userActivation: .none),
            tabContext: tabContext
        )
        XCTAssertTrue(storedAllow.isAllowed)
    }

    func testAutoplayCanonicalSettingFeedsBrowserConfigAndMarksActivePageReloadRequired() async throws {
        let container = try sumiPermissionIntegrationModelContainer()
        let store = SwiftDataPermissionStore(container: container)
        let adapter = SumiAutoplayPolicyStoreAdapter(modelContainer: container, persistentStore: store)
        let browserConfiguration = BrowserConfiguration(autoplayPolicyStore: adapter)
        let profile = sumiPermissionIntegrationProfile()
        let url = URL(string: "https://example.com/watch")!

        try await adapter.setPolicy(
            .blockAudible,
            for: url,
            profile: profile,
            source: .user,
            now: sumiPermissionIntegrationNow
        )

        let configuration = browserConfiguration.normalTabWebViewConfiguration(for: profile, url: url)
        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, .audio)
        XCTAssertEqual(adapter.explicitPolicy(for: url, profile: profile), .blockAudible)

        let activeConfiguration = WKWebViewConfiguration()
        activeConfiguration.mediaTypesRequiringUserActionForPlayback = []
        let activeWebView = WKWebView(frame: .zero, configuration: activeConfiguration)
        let runtimeController = FakeSumiRuntimePermissionController(autoplayRuntimeState: .allowAll)
        let runtimeResult = runtimeController.evaluateAutoplayPolicyChange(.blockAudible, for: activeWebView)
        guard case .requiresReload(let requirement) = runtimeResult else {
            return XCTFail("Expected active autoplay policy changes to require page rebuild")
        }
        XCTAssertEqual(requirement.kind, .rebuild)
        XCTAssertEqual(requirement.permissionType, .autoplay)
        XCTAssertEqual(requirement.requestedAutoplayState, .blockAudible)

        let controls = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: runtimeController.currentRuntimeState(for: activeWebView, pageId: "tab-a:1"),
            reloadRequired: true,
            displayDomain: "example.com"
        )
        XCTAssertEqual(
            controls.first { $0.permissionType == .autoplay }?.actions.map(\.kind),
            [.reloadAutoplay]
        )
    }

    private func makeHarness() -> (
        store: SumiPermissionIntegrationStore,
        systemService: FakeSumiSystemPermissionService,
        runtimeController: FakeSumiRuntimePermissionController,
        coordinator: SumiPermissionCoordinator
    ) {
        let store = SumiPermissionIntegrationStore()
        let systemService = FakeSumiSystemPermissionService(
            states: sumiPermissionIntegrationAuthorizedSystemStates()
        )
        let coordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(systemPermissionService: systemService),
            memoryStore: InMemoryPermissionStore(),
            persistentStore: store,
            sessionOwnerId: "window-a",
            now: sumiPermissionIntegrationDate
        )
        return (store, systemService, FakeSumiRuntimePermissionController(), coordinator)
    }

    private func makeSettingsRepository(
        coordinator: any SumiPermissionCoordinating
    ) -> SumiPermissionSettingsRepository {
        SumiPermissionSettingsRepository(
            coordinator: coordinator,
            systemPermissionService: FakeSumiSystemPermissionService(
                states: sumiPermissionIntegrationAuthorizedSystemStates()
            ),
            recentActivityStore: SumiPermissionRecentActivityStore(),
            blockedPopupStore: SumiBlockedPopupStore(),
            externalSchemeSessionStore: SumiExternalSchemeSessionStore(),
            indicatorEventStore: SumiPermissionIndicatorEventStore(),
            websiteDataCleanupService: nil,
            permissionCleanupService: nil,
            userDefaults: UserDefaults(suiteName: "SumiPermissionEndToEndFlowTests-\(UUID().uuidString)")!,
            now: sumiPermissionIntegrationDate
        )
    }

    private func bridgeDecision(
        bridge: SumiWebKitPermissionBridge,
        request: SumiWebKitMediaCaptureRequest,
        tabContext: SumiWebKitMediaCaptureTabContext,
        webView: WKWebView
    ) -> Task<[WKPermissionDecision], Never> {
        Task { @MainActor in
            await withCheckedContinuation { continuation in
                var decisions: [WKPermissionDecision] = []
                bridge.handleMediaCaptureAuthorization(
                    request,
                    tabContext: tabContext,
                    webView: webView
                ) { decision in
                    decisions.append(decision)
                    continuation.resume(returning: decisions)
                }
            }
        }
    }

    private func geolocationDecision(
        bridge: SumiWebKitGeolocationBridge,
        request: SumiWebKitGeolocationRequest,
        tabContext: SumiWebKitGeolocationTabContext,
        webView: WKWebView
    ) -> Task<[WKPermissionDecision], Never> {
        Task { @MainActor in
            await withCheckedContinuation { continuation in
                var decisions: [WKPermissionDecision] = []
                bridge.handleGeolocationAuthorization(
                    request,
                    tabContext: tabContext,
                    webView: webView
                ) { decision in
                    decisions.append(decision)
                    continuation.resume(returning: decisions)
                }
            }
        }
    }

    private func storageDecision(
        bridge: SumiStorageAccessPermissionBridge,
        request: SumiStorageAccessRequest,
        tabContext: SumiStorageAccessTabContext,
        webView: WKWebView
    ) -> Task<[Bool], Never> {
        Task { @MainActor in
            await withCheckedContinuation { continuation in
                var decisions: [Bool] = []
                bridge.handleStorageAccessRequest(
                    request,
                    tabContext: tabContext,
                    webView: webView
                ) { granted in
                    decisions.append(granted)
                    continuation.resume(returning: decisions)
                }
            }
        }
    }

    private func mediaRequest(
        id: String,
        permissionTypes: [SumiPermissionType]
    ) -> SumiWebKitMediaCaptureRequest {
        SumiWebKitMediaCaptureRequest(
            id: id,
            webKitMediaTypeRawValue: 0,
            permissionTypes: permissionTypes,
            requestingOrigin: sumiPermissionIntegrationOrigin(),
            frameURL: URL(string: "https://example.com/page"),
            isMainFrame: true
        )
    }

    private func mediaTabContext(
        pageId: String = "tab-a:1",
        generation: String = "1"
    ) -> SumiWebKitMediaCaptureTabContext {
        SumiWebKitMediaCaptureTabContext(
            tabId: "tab-a",
            pageId: pageId,
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            committedURL: URL(string: "https://example.com/page"),
            visibleURL: URL(string: "https://example.com/page"),
            mainFrameURL: URL(string: "https://example.com/page"),
            isActiveTab: true,
            isVisibleTab: true,
            navigationOrPageGeneration: generation,
            isCurrentPage: { true }
        )
    }

    private func geolocationTabContext(
        pageId: String = "tab-a:1",
        generation: String = "1"
    ) -> SumiWebKitGeolocationTabContext {
        SumiWebKitGeolocationTabContext(
            tabId: "tab-a",
            pageId: pageId,
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            committedURL: URL(string: "https://example.com/page"),
            visibleURL: URL(string: "https://example.com/page"),
            mainFrameURL: URL(string: "https://example.com/page"),
            isActiveTab: true,
            isVisibleTab: true,
            navigationOrPageGeneration: generation,
            isCurrentPage: { true }
        )
    }

    private func storageAccessRequest(id: String) -> SumiStorageAccessRequest {
        SumiStorageAccessRequest(
            id: id,
            requestingDomain: "https://idp.example",
            currentDomain: "rp.example"
        )
    }

    private func storageAccessTabContext() -> SumiStorageAccessTabContext {
        SumiStorageAccessTabContext(
            tabId: "tab-a",
            pageId: "tab-a:1",
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            committedURL: URL(string: "https://rp.example/page"),
            visibleURL: URL(string: "https://rp.example/page"),
            mainFrameURL: URL(string: "https://rp.example/page"),
            isActiveTab: true,
            isVisibleTab: true,
            navigationOrPageGeneration: "1",
            isCurrentPage: { true }
        )
    }

    private func externalSchemeRequest(
        id: String,
        userActivation: SumiExternalSchemeUserActivationState
    ) -> SumiExternalSchemePermissionRequest {
        SumiExternalSchemePermissionRequest(
            id: id,
            path: .navigationResponder,
            targetURL: URL(string: "mailto:test@example.com"),
            sourceURL: URL(string: "https://example.com/page"),
            requestingOrigin: sumiPermissionIntegrationOrigin(),
            userActivation: userActivation,
            isMainFrame: true,
            isRedirectChain: false
        )
    }

    private func externalSchemeTabContext() -> SumiExternalSchemePermissionTabContext {
        SumiExternalSchemePermissionTabContext(
            tabId: "tab-a",
            pageId: "tab-a:1",
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            committedURL: URL(string: "https://example.com/page"),
            visibleURL: URL(string: "https://example.com/page"),
            mainFrameURL: URL(string: "https://example.com/page"),
            isActiveTab: true,
            isVisibleTab: true,
            navigationOrPageGeneration: "1",
            displayDomain: "example.com",
            isCurrentPage: { true }
        )
    }

    private func popupRequest(
        id: String,
        userActivation: SumiPopupUserActivationState
    ) -> SumiPopupPermissionRequest {
        SumiPopupPermissionRequest(
            id: id,
            path: .uiDelegateCreateWebView,
            targetURL: URL(string: "https://popup.example/landing"),
            sourceURL: URL(string: "https://example.com/page"),
            requestingOrigin: sumiPermissionIntegrationOrigin(),
            userActivation: userActivation,
            isMainFrame: false
        )
    }

    private func popupTabContext() -> SumiPopupPermissionTabContext {
        SumiPopupPermissionTabContext(
            tabId: "tab-a",
            pageId: "tab-a:1",
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            committedURL: URL(string: "https://example.com/page"),
            visibleURL: URL(string: "https://example.com/page"),
            mainFrameURL: URL(string: "https://example.com/page"),
            isActiveTab: true,
            isVisibleTab: true,
            navigationOrPageGeneration: "1",
            displayDomain: "example.com"
        )
    }
}
