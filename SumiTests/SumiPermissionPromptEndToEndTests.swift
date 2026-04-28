import WebKit
import XCTest

@testable import Sumi

@available(macOS 13.0, *)
@MainActor
final class SumiPermissionPromptEndToEndTests: XCTestCase {
    func testNotificationRequestPermissionDismissResolvesDefaultAndDoesNotPersist() async {
        let harness = makeHarness(systemStates: [.notifications: .authorized])
        let bridge = makeNotificationBridge(coordinator: harness.coordinator)

        let permissionTask = Task {
            await bridge.requestWebsitePermission(
                request: notificationRequest(id: "notification-dismiss"),
                tabContext: notificationTabContext()
            )
        }
        let query = await sumiPermissionIntegrationWaitForActiveQuery(harness.coordinator)

        let prompt = SumiPermissionPromptViewModel(
            query: query,
            coordinator: harness.coordinator,
            systemPermissionService: harness.systemService
        )
        await prompt.performAction(.dismiss)

        let permissionResult = await permissionTask.value
        let setDecisionCallCount = await harness.store.setDecisionCallCount()
        XCTAssertEqual(permissionResult, .default)
        XCTAssertEqual(setDecisionCallCount, 0)
    }

    func testNotificationAllowPersistsSiteAllowAndFutureStateIsGranted() async {
        let harness = makeHarness(systemStates: [.notifications: .authorized])
        let bridge = makeNotificationBridge(coordinator: harness.coordinator)

        let permissionTask = Task {
            await bridge.requestWebsitePermission(
                request: notificationRequest(id: "notification-allow"),
                tabContext: notificationTabContext()
            )
        }
        let query = await sumiPermissionIntegrationWaitForActiveQuery(harness.coordinator)
        let prompt = SumiPermissionPromptViewModel(
            query: query,
            coordinator: harness.coordinator,
            systemPermissionService: harness.systemService
        )
        await prompt.performAction(.allow)

        let permissionResult = await permissionTask.value
        let key = sumiPermissionIntegrationKey(.notifications)
        let storedState = await harness.store.record(for: key)?.decision.state
        XCTAssertEqual(permissionResult, .granted)
        XCTAssertEqual(storedState, .allow)

        let state = await bridge.currentWebsitePermissionState(
            request: notificationRequest(id: "notification-state"),
            tabContext: notificationTabContext()
        )
        XCTAssertEqual(state, .granted)
    }

    func testNotificationSystemDeniedReturnsDeniedWithoutSiteDenyOrSystemRequest() async {
        let harness = makeHarness(systemStates: [.notifications: .denied])
        let bridge = makeNotificationBridge(coordinator: harness.coordinator)

        let state = await bridge.requestWebsitePermission(
            request: notificationRequest(id: "notification-system-denied"),
            tabContext: notificationTabContext()
        )

        XCTAssertEqual(state, .denied)
        let activeQuery = await harness.coordinator.activeQuery(forPageId: "tab-a:1")
        let setDecisionCallCount = await harness.store.setDecisionCallCount()
        let systemRequestCount = await harness.systemService.requestAuthorizationCallCount(for: .notifications)
        XCTAssertNil(activeQuery)
        XCTAssertEqual(setDecisionCallCount, 0)
        XCTAssertEqual(systemRequestCount, 0)
    }

    func testScreenCapturePromptAndSystemDeniedPathsDoNotPersistSiteDeny() async {
        let allowedHarness = makeHarness(systemStates: [.screenCapture: .authorized])
        let allowedBridge = SumiWebKitPermissionBridge(
            coordinator: allowedHarness.coordinator,
            runtimeController: allowedHarness.runtimeController,
            now: sumiPermissionIntegrationDate
        )
        let webView = WKWebView()

        let promptTask = displayDecision(
            bridge: allowedBridge,
            request: displayRequest(id: "screen-prompt"),
            webView: webView
        )
        let query = await sumiPermissionIntegrationWaitForActiveQuery(allowedHarness.coordinator)
        XCTAssertEqual(query.permissionTypes, [.screenCapture])
        await allowedHarness.coordinator.cancel(queryId: query.id, reason: "test-cleanup")
        let promptDecision = await promptTask.value
        XCTAssertEqual(promptDecision, [SumiWebKitDisplayCapturePermissionDecision.deny.rawValue])

        let deniedHarness = makeHarness(systemStates: [.screenCapture: .denied])
        let deniedBridge = SumiWebKitPermissionBridge(
            coordinator: deniedHarness.coordinator,
            runtimeController: deniedHarness.runtimeController,
            now: sumiPermissionIntegrationDate
        )
        let denied = await displayDecision(
            bridge: deniedBridge,
            request: displayRequest(id: "screen-system-denied"),
            webView: webView
        ).value

        XCTAssertEqual(denied, [SumiWebKitDisplayCapturePermissionDecision.deny.rawValue])
        let deniedSetDecisionCallCount = await deniedHarness.store.setDecisionCallCount()
        XCTAssertEqual(deniedSetDecisionCallCount, 0)

        let controls = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(
                camera: .none,
                microphone: .none,
                screenCapture: .unsupported
            ),
            reloadRequired: false,
            displayDomain: "example.com"
        )
        XCTAssertFalse(controls.contains { $0.permissionType == .screenCapture })
    }

    func testSystemNotDeterminedIsRequestedFromPromptUIOnly() async {
        let harness = makeHarness(
            systemStates: [.camera: .notDetermined],
            requestResults: [.camera: .authorized]
        )

        let requestTask = Task {
            await harness.coordinator.requestPermission(
                sumiPermissionIntegrationContext([.camera], id: "camera-not-determined")
            )
        }
        let query = await sumiPermissionIntegrationWaitForActiveQuery(harness.coordinator)

        XCTAssertTrue(query.requiresSystemAuthorizationPrompt)
        let systemRequestCountBeforePrompt = await harness.systemService.requestAuthorizationCallCount(for: .camera)
        XCTAssertEqual(systemRequestCountBeforePrompt, 0)

        let prompt = SumiPermissionPromptViewModel(
            query: query,
            coordinator: harness.coordinator,
            systemPermissionService: harness.systemService
        )
        await prompt.performAction(.allowThisTime)

        let decision = await requestTask.value
        let systemRequestCountAfterPrompt = await harness.systemService.requestAuthorizationCallCount(for: .camera)
        XCTAssertEqual(decision.outcome, .granted)
        XCTAssertEqual(systemRequestCountAfterPrompt, 1)
    }

    private func makeHarness(
        systemStates: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState],
        requestResults: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState] = [:]
    ) -> (
        store: SumiPermissionIntegrationStore,
        systemService: FakeSumiSystemPermissionService,
        runtimeController: FakeSumiRuntimePermissionController,
        coordinator: SumiPermissionCoordinator
    ) {
        let store = SumiPermissionIntegrationStore()
        var states = sumiPermissionIntegrationAuthorizedSystemStates()
        for (kind, state) in systemStates {
            states[kind] = state
        }
        let systemService = FakeSumiSystemPermissionService(
            states: states,
            requestResults: requestResults
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

    private func makeNotificationBridge(
        coordinator: any SumiPermissionCoordinating
    ) -> SumiNotificationPermissionBridge {
        SumiNotificationPermissionBridge(
            coordinator: coordinator,
            notificationService: FakeSumiNotificationService(),
            now: sumiPermissionIntegrationDate
        )
    }

    private func notificationRequest(id: String) -> SumiWebNotificationRequest {
        SumiWebNotificationRequest(
            id: id,
            requestingOrigin: sumiPermissionIntegrationOrigin(),
            frameURL: URL(string: "https://example.com/page"),
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
            navigationOrPageGeneration: "1",
            displayDomain: "example.com",
            isCurrentPage: { true }
        )
    }

    private func displayDecision(
        bridge: SumiWebKitPermissionBridge,
        request: SumiWebKitDisplayCaptureRequest,
        webView: WKWebView
    ) -> Task<[Int], Never> {
        Task { @MainActor in
            await withCheckedContinuation { continuation in
                var decisions: [Int] = []
                bridge.handleDisplayCaptureAuthorization(
                    request,
                    tabContext: SumiWebKitMediaCaptureTabContext(
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
                        isCurrentPage: { true }
                    ),
                    webView: webView
                ) { decision in
                    decisions.append(decision)
                    continuation.resume(returning: decisions)
                }
            }
        }
    }

    private func displayRequest(id: String) -> SumiWebKitDisplayCaptureRequest {
        SumiWebKitDisplayCaptureRequest(
            id: id,
            webKitDisplayCaptureTypeRawValue: SumiWebKitDisplayCapturePermissionDecision.screenPrompt.rawValue,
            permissionTypes: [.screenCapture],
            requestingOrigin: sumiPermissionIntegrationOrigin(),
            frameURL: URL(string: "https://example.com/page"),
            isMainFrame: true,
            withSystemAudio: false
        )
    }
}
