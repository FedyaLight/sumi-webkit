import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionCleanupServiceTests: XCTestCase {
    func testDisabledCleanupDoesNothing() async throws {
        let harness = try CleanupHarness()
        let key = harness.key(.camera)
        try await harness.store.setDecision(
            for: key,
            decision: harness.decision(.allow, updatedAt: harness.oldDate)
        )

        let result = await harness.service.run(
            profile: harness.profile,
            settings: SumiPermissionCleanupSettings(isAutomaticCleanupEnabled: false),
            force: true
        )

        XCTAssertEqual(result.removedCount, 0)
        let record = try await harness.store.getDecision(for: key)
        XCTAssertNotNil(record)
    }

    func testStalePersistentAllowsAreRemovedAndFreshAllowsAreRetained() async throws {
        let harness = try CleanupHarness()
        let stale = harness.key(.camera)
        let fresh = harness.key(.microphone)

        try await harness.store.setDecision(
            for: stale,
            decision: harness.decision(.allow, updatedAt: harness.oldDate)
        )
        try await harness.store.setDecision(
            for: fresh,
            decision: harness.decision(.allow, updatedAt: harness.recentDate)
        )

        let result = await harness.runEnabled()

        XCTAssertEqual(result.removedCount, 1)
        let staleRecord = try await harness.store.getDecision(for: stale)
        let freshRecord = try await harness.store.getDecision(for: fresh)
        XCTAssertNil(staleRecord)
        XCTAssertNotNil(freshRecord)
    }

    func testPersistentDenyAskAndFilePickerAreRetainedOrIgnored() async throws {
        let harness = try CleanupHarness()
        let deny = harness.key(.camera)
        let ask = harness.key(.microphone)

        try await harness.store.setDecision(
            for: deny,
            decision: harness.decision(.deny, updatedAt: harness.oldDate)
        )
        try await harness.store.setDecision(
            for: ask,
            decision: harness.decision(.ask, updatedAt: harness.oldDate)
        )

        let result = await harness.runEnabled()

        XCTAssertEqual(result.removedCount, 0)
        let denyRecord = try await harness.store.getDecision(for: deny)
        let askRecord = try await harness.store.getDecision(for: ask)
        XCTAssertNotNil(denyRecord)
        XCTAssertNotNil(askRecord)
    }

    func testLastUsedAtIsPreferredOverUpdatedAtForStaleness() async throws {
        let harness = try CleanupHarness()
        let key = harness.key(.camera)
        try await harness.store.setDecision(
            for: key,
            decision: harness.decision(
                .allow,
                updatedAt: harness.oldDate,
                lastUsedAt: harness.recentDate
            )
        )

        let result = await harness.runEnabled()

        XCTAssertEqual(result.removedCount, 0)
        let record = try await harness.store.getDecision(for: key)
        XCTAssertNotNil(record)
    }

    func testExternalSchemeCleanupRemovesOnlyExactSchemeKey() async throws {
        let harness = try CleanupHarness()
        let zoom = harness.key(.externalScheme("zoommtg"))
        let slack = harness.key(.externalScheme("slack"))

        try await harness.store.setDecision(
            for: zoom,
            decision: harness.decision(.allow, updatedAt: harness.oldDate)
        )
        try await harness.store.setDecision(
            for: slack,
            decision: harness.decision(.allow, updatedAt: harness.recentDate)
        )

        let result = await harness.runEnabled()

        XCTAssertEqual(result.removedEvents.map { $0.key.permissionType.identity }, ["external-scheme:zoommtg"])
        let zoomRecord = try await harness.store.getDecision(for: zoom)
        let slackRecord = try await harness.store.getDecision(for: slack)
        XCTAssertNil(zoomRecord)
        XCTAssertNotNil(slackRecord)
    }

    func testLaunchCleanupIsThrottledPerProfile() async throws {
        let harness = try CleanupHarness()
        let key = harness.key(.camera)
        try await harness.store.setDecision(
            for: key,
            decision: harness.decision(.allow, updatedAt: harness.oldDate)
        )

        let first = await harness.service.runIfNeeded(
            profile: harness.profile,
            settings: harness.enabledSettings
        )
        let second = await harness.service.runIfNeeded(
            profile: harness.profile,
            settings: harness.enabledSettings
        )

        XCTAssertEqual(first.removedCount, 1)
        XCTAssertTrue(second.wasThrottled)
    }
}

@MainActor
struct CleanupHarness {
    let modelContainer: ModelContainer
    let store: SwiftDataPermissionStore
    let recentActivityStore: SumiPermissionRecentActivityStore
    let userDefaults: UserDefaults
    let service: SumiPermissionCleanupService
    let profile = SumiPermissionSettingsProfileContext(
        profilePartitionId: "profile-a",
        isEphemeralProfile: false,
        profileName: "Work"
    )
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let container = try ModelContainer(
            for: Schema([PermissionDecisionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = SwiftDataPermissionStore(container: container)
        let recentActivityStore = SumiPermissionRecentActivityStore()
        let userDefaults = UserDefaults(suiteName: "SumiCleanupServiceTests-\(UUID().uuidString)")!

        self.modelContainer = container
        self.store = store
        self.recentActivityStore = recentActivityStore
        self.userDefaults = userDefaults
        self.service = SumiPermissionCleanupService(
            store: store,
            recentActivityStore: recentActivityStore,
            antiAbuseStore: SumiPermissionAntiAbuseStore.memoryOnly(),
            userDefaults: userDefaults,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    var oldDate: Date {
        now.addingTimeInterval(-SumiPermissionCleanupSettings.defaultThreshold - 60)
    }

    var recentDate: Date {
        now.addingTimeInterval(-60)
    }

    var enabledSettings: SumiPermissionCleanupSettings {
        SumiPermissionCleanupSettings(isAutomaticCleanupEnabled: true)
    }

    func runEnabled() async -> SumiPermissionCleanupResult {
        await service.run(profile: profile, settings: enabledSettings, force: true)
    }

    func key(
        _ type: SumiPermissionType,
        requestingOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://example.com"),
        topOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://example.com"),
        profileId: String = "profile-a"
    ) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            permissionType: type,
            profilePartitionId: profileId,
            isEphemeralProfile: false
        )
    }

    func decision(
        _ state: SumiPermissionState,
        updatedAt: Date,
        lastUsedAt: Date? = nil
    ) -> SumiPermissionDecision {
        SumiPermissionDecision(
            state: state,
            persistence: .persistent,
            source: .user,
            reason: "test",
            createdAt: updatedAt.addingTimeInterval(-60),
            updatedAt: updatedAt,
            lastUsedAt: lastUsedAt
        )
    }
}
