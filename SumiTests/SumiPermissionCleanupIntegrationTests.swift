import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionCleanupIntegrationTests: XCTestCase {
    func testCleanupToggleChangesSettingsOnlyUntilServiceRuns() async throws {
        let harness = try CleanupHarness()
        let stale = harness.key(.camera)
        try await harness.store.setDecision(
            for: stale,
            decision: harness.decision(.allow, updatedAt: harness.oldDate)
        )
        let repository = SumiPermissionSettingsRepository(
            coordinator: CleanupIntegrationCoordinator(store: harness.store),
            systemPermissionService: FakeSumiSystemPermissionService(
                states: sumiPermissionIntegrationAuthorizedSystemStates()
            ),
            autoplayStore: SumiAutoplayPolicyStoreAdapter(
                modelContainer: harness.modelContainer,
                persistentStore: harness.store
            ),
            recentActivityStore: harness.recentActivityStore,
            blockedPopupStore: SumiBlockedPopupStore(),
            externalSchemeSessionStore: SumiExternalSchemeSessionStore(),
            indicatorEventStore: SumiPermissionIndicatorEventStore(),
            websiteDataCleanupService: nil,
            permissionCleanupService: harness.service,
            userDefaults: harness.userDefaults,
            now: { harness.now }
        )
        let viewModel = SumiSiteSettingsViewModel(repository: repository)

        repository.setAutomaticCleanupEnabled(true, profile: harness.profile)
        await viewModel.load(profile: nil)

        XCTAssertTrue(repository.cleanupSettings.isAutomaticCleanupEnabled)
        let staleBeforeCleanup = try await harness.store.getDecision(for: stale)
        XCTAssertNotNil(staleBeforeCleanup)

        let result = await repository.runCleanup(profile: harness.profile, force: true)

        XCTAssertEqual(result.removedCount, 1)
        let staleAfterCleanup = try await harness.store.getDecision(for: stale)
        XCTAssertNil(staleAfterCleanup)
        XCTAssertEqual(
            harness.recentActivityStore.records(
                profilePartitionId: harness.profile.profilePartitionId,
                isEphemeralProfile: false
            ).first?.action,
            .autoRevoked
        )
    }

    func testCleanupRemovesOnlyStalePersistentAllowsAndPreservesOtherDecisions() async throws {
        let harness = try CleanupHarness()
        let staleAllow = harness.key(.camera)
        let freshAllow = harness.key(.microphone)
        let staleDeny = harness.key(.notifications)
        let staleAsk = harness.key(.popups)

        try await harness.store.setDecision(
            for: staleAllow,
            decision: harness.decision(.allow, updatedAt: harness.oldDate)
        )
        try await harness.store.setDecision(
            for: freshAllow,
            decision: harness.decision(.allow, updatedAt: harness.recentDate)
        )
        try await harness.store.setDecision(
            for: staleDeny,
            decision: harness.decision(.deny, updatedAt: harness.oldDate)
        )
        try await harness.store.setDecision(
            for: staleAsk,
            decision: harness.decision(.ask, updatedAt: harness.oldDate)
        )

        let result = await harness.runEnabled()

        XCTAssertEqual(result.removedEvents.map { $0.key.permissionType }, [.camera])
        let staleAllowAfterCleanup = try await harness.store.getDecision(for: staleAllow)
        let freshAllowAfterCleanup = try await harness.store.getDecision(for: freshAllow)
        let staleDenyAfterCleanup = try await harness.store.getDecision(for: staleDeny)
        let staleAskAfterCleanup = try await harness.store.getDecision(for: staleAsk)
        XCTAssertNil(staleAllowAfterCleanup)
        XCTAssertNotNil(freshAllowAfterCleanup)
        XCTAssertNotNil(staleDenyAfterCleanup)
        XCTAssertNotNil(staleAskAfterCleanup)
    }

    func testCleanupSourceDoesNotReferenceSiteDataCookieOrTrackingDeletionAPIs() throws {
        let cleanupSource = try sourceFile("Sumi/Permissions/SumiPermissionCleanupService.swift")
        let repositorySource = try sourceFile("Sumi/Permissions/SumiPermissionSettingsRepository.swift")
        let cleanupRange = try XCTUnwrap(cleanupSource.range(of: "final class SumiPermissionCleanupService"))
        let cleanupBody = String(cleanupSource[cleanupRange.lowerBound...])

        XCTAssertFalse(cleanupBody.contains("removeWebsiteData"))
        XCTAssertFalse(cleanupBody.contains("clearAllProfileWebsiteData"))
        XCTAssertFalse(cleanupBody.contains("HTTPCookie"))
        XCTAssertFalse(cleanupBody.contains("TrackingProtection"))
        XCTAssertTrue(repositorySource.contains("permissionCleanupService.run("))
        XCTAssertTrue(repositorySource.contains("removeWebsiteDataForExactHost"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

private actor CleanupIntegrationCoordinator: SumiPermissionCoordinating {
    let store: SwiftDataPermissionStore

    init(store: SwiftDataPermissionStore) {
        self.store = store
    }

    func requestPermission(_ context: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .promptRequired,
            state: .ask,
            persistence: nil,
            source: .defaultSetting,
            reason: "fake",
            permissionTypes: context.request.permissionTypes
        )
    }

    func queryPermissionState(_ context: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        await requestPermission(context)
    }

    func siteDecisionRecords(
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) async throws -> [SumiPermissionStoreRecord] {
        guard !isEphemeralProfile else { return [] }
        return try await store.listDecisions(profilePartitionId: profilePartitionId)
    }

    func setSiteDecision(
        for key: SumiPermissionKey,
        state: SumiPermissionState,
        source: SumiPermissionDecisionSource,
        reason: String?
    ) async throws {
        try await store.setDecision(
            for: key,
            decision: SumiPermissionDecision(
                state: state,
                persistence: .persistent,
                source: source,
                reason: reason,
                createdAt: sumiPermissionIntegrationNow,
                updatedAt: sumiPermissionIntegrationNow
            )
        )
    }

    func resetSiteDecision(for key: SumiPermissionKey) async throws {
        try await store.resetDecision(for: key)
    }

    func activeQuery(forPageId pageId: String) async -> SumiPermissionAuthorizationQuery? { nil }
    func stateSnapshot() async -> SumiPermissionCoordinatorState { SumiPermissionCoordinatorState() }
    func events() async -> AsyncStream<SumiPermissionCoordinatorEvent> {
        AsyncStream { $0.finish() }
    }

    @discardableResult func cancel(queryId: String, reason: String) async -> SumiPermissionCoordinatorDecision {
        ignored(reason)
    }
    @discardableResult func cancel(requestId: String, reason: String) async -> SumiPermissionCoordinatorDecision {
        ignored(reason)
    }
    @discardableResult func cancel(pageId: String, reason: String) async -> SumiPermissionCoordinatorDecision {
        ignored(reason)
    }
    @discardableResult func cancelNavigation(pageId: String, reason: String) async -> SumiPermissionCoordinatorDecision {
        ignored(reason)
    }
    @discardableResult func cancelTab(tabId: String, reason: String) async -> SumiPermissionCoordinatorDecision {
        ignored(reason)
    }

    private func ignored(_ reason: String) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .ignored,
            state: nil,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: []
        )
    }
}
