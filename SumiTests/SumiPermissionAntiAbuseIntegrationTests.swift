import WebKit
import XCTest

@testable import Sumi

@available(macOS 13.0, *)
@MainActor
final class SumiPermissionAntiAbuseIntegrationTests: XCTestCase {
    func testDismissCooldownSuppressesNotificationPromptAsDefaultWithoutPersistentDeny() async {
        var now = sumiPermissionIntegrationNow
        let store = SumiPermissionIntegrationStore()
        let antiAbuseStore = SumiPermissionAntiAbuseStore.memoryOnly()
        let system = FakeSumiSystemPermissionService(
            states: sumiPermissionIntegrationAuthorizedSystemStates()
        )
        let coordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(systemPermissionService: system),
            memoryStore: InMemoryPermissionStore(),
            persistentStore: store,
            antiAbuseStore: antiAbuseStore,
            now: { now }
        )
        let bridge = SumiNotificationPermissionBridge(
            coordinator: coordinator,
            notificationService: FakeSumiNotificationService(),
            now: { now }
        )

        let firstTask = Task {
            await bridge.requestWebsitePermission(
                request: notificationRequest(id: "notification-first"),
                tabContext: notificationTabContext()
            )
        }
        let query = await sumiPermissionIntegrationWaitForActiveQuery(coordinator)
        await coordinator.recordPromptShown(queryId: query.id)
        let prompt = SumiPermissionPromptViewModel(
            query: query,
            coordinator: coordinator,
            systemPermissionService: system
        )
        await prompt.performAction(.dismiss)
        let firstResult = await firstTask.value
        XCTAssertEqual(firstResult, .default)

        now = sumiPermissionIntegrationNow.addingTimeInterval(60)
        let second = await bridge.requestWebsitePermission(
            request: notificationRequest(id: "notification-second"),
            tabContext: notificationTabContext()
        )

        XCTAssertEqual(second, .default)
        let activeQuery = await coordinator.activeQuery(forPageId: "tab-a:1")
        let setDecisionCallCount = await store.setDecisionCallCount()
        XCTAssertNil(activeQuery)
        XCTAssertEqual(setDecisionCallCount, 0)

        let decision = await coordinator.requestPermission(
            sumiPermissionIntegrationContext([.notifications], id: "notification-third")
        )
        XCTAssertEqual(decision.outcome, .suppressed)
        XCTAssertEqual(decision.promptSuppression?.trigger, .dismissal)
    }

    func testManualAllowClearsSuppressionForExactPermissionKey() async throws {
        var now = sumiPermissionIntegrationNow
        let store = SumiPermissionIntegrationStore()
        let antiAbuseStore = SumiPermissionAntiAbuseStore.memoryOnly()
        let coordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: FakeSumiSystemPermissionService(
                    states: sumiPermissionIntegrationAuthorizedSystemStates()
                )
            ),
            memoryStore: InMemoryPermissionStore(),
            persistentStore: store,
            antiAbuseStore: antiAbuseStore,
            now: { now }
        )

        let firstTask = Task {
            await coordinator.requestPermission(
                sumiPermissionIntegrationContext([.camera], id: "camera-first")
            )
        }
        let firstQuery = await sumiPermissionIntegrationWaitForActiveQuery(coordinator)
        await coordinator.recordPromptShown(queryId: firstQuery.id)
        await coordinator.dismiss(firstQuery.id)
        _ = await firstTask.value

        now = sumiPermissionIntegrationNow.addingTimeInterval(60)
        let suppressed = await coordinator.requestPermission(
            sumiPermissionIntegrationContext([.camera], id: "camera-suppressed")
        )
        XCTAssertEqual(suppressed.outcome, .suppressed)

        try await coordinator.setSiteDecision(
            for: sumiPermissionIntegrationKey(.camera),
            state: .allow,
            source: .user,
            reason: "url-hub-manual-allow"
        )

        let allowed = await coordinator.requestPermission(
            sumiPermissionIntegrationContext([.camera], id: "camera-after-manual-allow")
        )
        XCTAssertEqual(allowed.outcome, .granted)
        let storedState = await store.record(for: sumiPermissionIntegrationKey(.camera))?.decision.state
        XCTAssertEqual(storedState, .allow)
    }

    func testSuppressionSourceDoesNotPersistDenyInCoordinatorOrBridgeCode() throws {
        let coordinatorSource = try sourceFile("Sumi/Permissions/SumiPermissionCoordinator.swift")
        let notificationSource = try sourceFile("Sumi/Permissions/SumiNotificationPermissionBridge.swift")

        let suppressionRange = try XCTUnwrap(coordinatorSource.range(of: "private func promptSuppressedDecision"))
        let suppressionTail = coordinatorSource[suppressionRange.lowerBound...]
        let suppressionBody = String(suppressionTail.prefix(2_400))

        XCTAssertTrue(suppressionBody.contains("outcome: .suppressed"))
        XCTAssertTrue(suppressionBody.contains("shouldPersist: false"))
        XCTAssertFalse(suppressionBody.contains("persistentStore.setDecision"))
        XCTAssertFalse(suppressionBody.contains("state: .deny"))
        XCTAssertFalse(notificationSource.contains("denyPersistently"))
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

    private func sourceFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
