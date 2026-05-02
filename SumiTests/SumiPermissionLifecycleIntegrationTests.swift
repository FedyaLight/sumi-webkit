import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionLifecycleIntegrationTests: XCTestCase {
    func testLifecycleNavigationClearsOneTimeGrantAndPendingQueries() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: LifecycleIntegrationPolicyResolver(),
            persistentStore: LifecycleIntegrationPersistentStore(),
            now: lifecycleIntegrationDate
        )
        let blockedPopupStore = SumiBlockedPopupStore()
        let externalSchemeStore = SumiExternalSchemeSessionStore()
        let indicatorStore = SumiPermissionIndicatorEventStore()
        let lifecycle = SumiPermissionGrantLifecycleController(
            coordinator: coordinator,
            geolocationProvider: nil,
            filePickerBridge: nil,
            indicatorEventStore: indicatorStore,
            blockedPopupStore: blockedPopupStore,
            externalSchemeSessionStore: externalSchemeStore
        )

        let grantTask = Task {
            await coordinator.requestPermission(
                lifecycleContext(.camera, id: "camera-grant", pageId: "tab-a:1")
            )
        }
        let grantQuery = await waitForIntegrationActiveQuery(coordinator, pageId: "tab-a:1")
        await coordinator.approveOnce(grantQuery.id)
        _ = await grantTask.value
        let repeatedGrant = await coordinator.requestPermission(
            lifecycleContext(.camera, id: "camera-repeat", pageId: "tab-a:1")
        )
        XCTAssertEqual(repeatedGrant.outcome, .granted)

        let pendingTask = Task {
            await coordinator.requestPermission(
                lifecycleContext(.microphone, id: "microphone-pending", pageId: "tab-a:1")
            )
        }
        _ = await waitForIntegrationActiveQuery(coordinator, pageId: "tab-a:1")

        lifecycle.handle(
            .mainFrameNavigation(
                pageId: "tab-a:1",
                tabId: "tab-a",
                profilePartitionId: "profile-a",
                targetURL: URL(string: "https://example.com/next"),
                reason: "test-main-frame-navigation"
            )
        )

        let pendingDecision = await pendingTask.value
        let afterNavigation = await eventuallyIntegrationDecision {
            await coordinator.queryPermissionState(
                lifecycleContext(.camera, id: "camera-after-nav", pageId: "tab-a:1")
            )
        }

        XCTAssertEqual(pendingDecision.outcome, .cancelled)
        XCTAssertEqual(afterNavigation.outcome, .promptRequired)
    }

    func testLifecycleTabCloseClearsAllTabOneTimeGenerations() async throws {
        let memoryStore = InMemoryPermissionStore()
        let coordinator = SumiPermissionCoordinator(
            policyResolver: LifecycleIntegrationPolicyResolver(),
            memoryStore: memoryStore,
            persistentStore: LifecycleIntegrationPersistentStore(),
            now: lifecycleIntegrationDate
        )
        let lifecycle = SumiPermissionGrantLifecycleController(
            coordinator: coordinator,
            geolocationProvider: nil,
            filePickerBridge: nil,
            indicatorEventStore: SumiPermissionIndicatorEventStore(),
            blockedPopupStore: SumiBlockedPopupStore(),
            externalSchemeSessionStore: SumiExternalSchemeSessionStore()
        )
        let pageOneKey = lifecycleKey(.camera, pageId: "tab-a:1")
        let pageTwoKey = lifecycleKey(.camera, pageId: "tab-a:2")
        try await memoryStore.setDecision(
            for: pageOneKey,
            decision: lifecycleDecision(.allow, persistence: .oneTime)
        )
        try await memoryStore.setDecision(
            for: pageTwoKey,
            decision: lifecycleDecision(.allow, persistence: .oneTime)
        )

        lifecycle.handle(
            .tabClosed(
                pageId: "tab-a:2",
                tabId: "tab-a",
                profilePartitionId: "profile-a",
                reason: "test-tab-close"
            )
        )

        let pageOne = await eventuallyIntegrationDecision {
            await coordinator.queryPermissionState(
                lifecycleContext(.camera, id: "camera-page-one", pageId: "tab-a:1")
            )
        }
        let pageTwo = await coordinator.queryPermissionState(
            lifecycleContext(.camera, id: "camera-page-two", pageId: "tab-a:2")
        )

        XCTAssertEqual(pageOne.outcome, .promptRequired)
        XCTAssertEqual(pageTwo.outcome, .promptRequired)
    }

}

private actor LifecycleIntegrationPolicyResolver: SumiPermissionPolicyResolver {
    func evaluate(_ context: SumiPermissionSecurityContext) async -> SumiPermissionPolicyResult {
        .proceed(
            source: .defaultSetting,
            reason: SumiPermissionPolicyReason.allowed,
            systemAuthorizationSnapshot: nil,
            mayOpenSystemSettings: false,
            allowedPersistences: [.oneTime, .session, .persistent]
        )
    }
}

private actor LifecycleIntegrationPersistentStore: SumiPermissionStore {
    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord? { nil }
    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async throws {}
    func resetDecision(for key: SumiPermissionKey) async throws {}
    func listDecisions(profilePartitionId: String) async throws -> [SumiPermissionStoreRecord] { [] }
    func listDecisions(forDisplayDomain displayDomain: String, profilePartitionId: String) async throws -> [SumiPermissionStoreRecord] { [] }
    func clearAll(profilePartitionId: String) async throws {}
    func clearForDisplayDomains(_ displayDomains: Set<String>, profilePartitionId: String) async throws {}
    func clearForOrigins(_ origins: Set<SumiPermissionOrigin>, profilePartitionId: String) async throws {}
    @discardableResult func expireDecisions(now: Date) async throws -> Int { 0 }
    func recordLastUsed(for key: SumiPermissionKey, at date: Date) async throws {}
}

private func lifecycleContext(
    _ permissionType: SumiPermissionType,
    id: String,
    pageId: String
) -> SumiPermissionSecurityContext {
    let request = SumiPermissionRequest(
        id: id,
        tabId: "tab-a",
        pageId: pageId,
        requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
        topOrigin: SumiPermissionOrigin(string: "https://example.com"),
        permissionTypes: [permissionType],
        requestedAt: lifecycleIntegrationDate(),
        profilePartitionId: "profile-a"
    )
    return SumiPermissionSecurityContext(
        request: request,
        committedURL: URL(string: "https://example.com"),
        visibleURL: URL(string: "https://example.com"),
        mainFrameURL: URL(string: "https://example.com"),
        transientPageId: pageId,
        now: lifecycleIntegrationDate()
    )
}

private func lifecycleKey(
    _ permissionType: SumiPermissionType,
    pageId: String
) -> SumiPermissionKey {
    SumiPermissionKey(
        requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
        topOrigin: SumiPermissionOrigin(string: "https://example.com"),
        permissionType: permissionType,
        profilePartitionId: "profile-a",
        transientPageId: pageId
    )
}

private func lifecycleDecision(
    _ state: SumiPermissionState,
    persistence: SumiPermissionPersistence
) -> SumiPermissionDecision {
    SumiPermissionDecision(
        state: state,
        persistence: persistence,
        source: .user,
        reason: "test",
        createdAt: lifecycleIntegrationDate(),
        updatedAt: lifecycleIntegrationDate()
    )
}

private func waitForIntegrationActiveQuery(
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
    XCTFail("Timed out waiting for permission query", file: file, line: line)
    return SumiPermissionAuthorizationQuery(
        id: "missing",
        pageId: pageId,
        profilePartitionId: "profile-a",
        displayDomain: "missing",
        requestingOrigin: .invalid(),
        topOrigin: .invalid(),
        permissionTypes: [],
        presentationPermissionType: nil,
        availablePersistences: [],
        systemAuthorizationSnapshots: [],
        policyReasons: [],
        createdAt: lifecycleIntegrationDate(),
        isEphemeralProfile: false,
        shouldOfferSystemSettings: false,
        disablesPersistentAllow: false,
    )
}

private func eventuallyIntegrationDecision(
    _ operation: () async -> SumiPermissionCoordinatorDecision,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> SumiPermissionCoordinatorDecision {
    var last = await operation()
    for _ in 0..<100 where last.outcome != .promptRequired {
        try? await Task.sleep(nanoseconds: 10_000_000)
        last = await operation()
    }
    if last.outcome != .promptRequired {
        XCTFail("Timed out waiting for prompt-required decision", file: file, line: line)
    }
    return last
}

private func lifecycleIntegrationDate() -> Date {
    ISO8601DateFormatter().date(from: "2026-04-28T10:00:00Z")!
}
