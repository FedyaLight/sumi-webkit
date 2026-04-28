import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionSiteSettingsIntegrationTests: XCTestCase {
    func testMainCategorySiteDetailAndExactOriginGrouping() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let embedded = SumiPermissionOrigin(string: "https://cdn.example")
        let top = SumiPermissionOrigin(string: "https://news.example")
        let otherProfile = Profile(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            name: "Other",
            icon: "person"
        )

        await harness.coordinator.seed(key: harness.key(.microphone), state: .allow)
        await harness.coordinator.seed(
            key: harness.key(.storageAccess, requestingOrigin: embedded, topOrigin: top),
            state: .deny
        )
        await harness.coordinator.seed(key: harness.key(.camera, profile: otherProfile), state: .allow)

        let viewModel = SumiSiteSettingsViewModel(repository: harness.repository)
        await viewModel.load(profile: harness.profile)

        XCTAssertEqual(viewModel.categoryRows.map(\.category), SumiSiteSettingsPermissionCategory.allCases)
        XCTAssertEqual(viewModel.categoryRows.first { $0.category == .microphone }?.exceptionCount, 1)
        XCTAssertEqual(viewModel.categoryRows.first { $0.category == .storageAccess }?.exceptionCount, 1)
        XCTAssertEqual(viewModel.siteRows.count, 2)
        XCTAssertTrue(viewModel.siteRows.contains { $0.scope.requestingOrigin.identity == "https://example.com" })
        XCTAssertTrue(viewModel.siteRows.contains {
            $0.scope.requestingOrigin.identity == "https://cdn.example"
                && $0.scope.topOrigin.identity == "https://news.example"
        })
        XCTAssertFalse(viewModel.siteRows.contains { $0.scope.profilePartitionId == otherProfile.id.uuidString.lowercased() })

        let category = SumiSiteSettingsCategoryViewModel(category: .storageAccess, repository: harness.repository)
        await category.load(profile: harness.profile)
        XCTAssertEqual(category.detail?.rows.map(\.scope.requestingOrigin.identity), ["https://cdn.example"])

        let scope = try XCTUnwrap(viewModel.siteRows.first {
            $0.scope.requestingOrigin.identity == "https://example.com"
        }?.scope)
        let detail = SumiSiteSettingsSiteDetailViewModel(scope: scope, repository: harness.repository)
        await detail.load(profile: harness.profile)
        XCTAssertEqual(
            detail.detail?.permissionRows.first { $0.kind == .sitePermission(.microphone) }?.currentOption,
            .allow
        )
        XCTAssertTrue(detail.detail?.permissionRows.contains { $0.kind == .filePicker } == false)
    }

    func testSiteDetailEditsDecisionsAndOneTimeSessionGrantsStayOutOfPersistentExceptions() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let memoryStore = InMemoryPermissionStore()
        let store = SumiPermissionIntegrationStore()
        let coordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: FakeSumiSystemPermissionService(
                    states: sumiPermissionIntegrationAuthorizedSystemStates()
                )
            ),
            memoryStore: memoryStore,
            persistentStore: store,
            sessionOwnerId: "window-a",
            now: sumiPermissionIntegrationDate
        )
        let container = try sumiPermissionIntegrationModelContainer()
        let permissionStore = SwiftDataPermissionStore(container: container)
        let repository = SumiPermissionSettingsRepository(
            coordinator: coordinator,
            systemPermissionService: FakeSumiSystemPermissionService(
                states: sumiPermissionIntegrationAuthorizedSystemStates()
            ),
            autoplayStore: SumiAutoplayPolicyStoreAdapter(
                modelContainer: container,
                persistentStore: permissionStore
            ),
            recentActivityStore: SumiPermissionRecentActivityStore(),
            blockedPopupStore: SumiBlockedPopupStore(),
            externalSchemeSessionStore: SumiExternalSchemeSessionStore(),
            indicatorEventStore: SumiPermissionIndicatorEventStore(),
            websiteDataCleanupService: harness.websiteDataService,
            permissionCleanupService: nil,
            userDefaults: UserDefaults(suiteName: "SumiPermissionSiteSettingsIntegrationTests-\(UUID().uuidString)")!,
            now: sumiPermissionIntegrationDate
        )

        try await memoryStore.setDecision(
            for: sumiPermissionIntegrationKey(.camera, pageId: "tab-a:1"),
            decision: sumiPermissionIntegrationDecision(.allow, persistence: .oneTime),
            sessionOwnerId: "window-a"
        )
        try await memoryStore.setDecision(
            for: sumiPermissionIntegrationKey(.geolocation, pageId: nil),
            decision: sumiPermissionIntegrationDecision(.allow, persistence: .session),
            sessionOwnerId: "window-a"
        )

        var rows = try await repository.siteRows(profile: profileContext)
        XCTAssertTrue(rows.isEmpty)

        let scope = SumiPermissionSiteScope(
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            requestingOrigin: sumiPermissionIntegrationOrigin(),
            topOrigin: sumiPermissionIntegrationOrigin(),
            displayDomain: "example.com"
        )
        let detail = try await repository.siteDetail(
            scope: scope,
            profile: profileContext,
            profileObject: nil,
            includeDataSummary: false
        )
        let camera = try XCTUnwrap(detail.permissionRows.first { $0.kind == .sitePermission(.camera) })
        try await repository.setOption(.allow, for: camera)

        rows = try await repository.siteRows(profile: profileContext)
        let storedCameraState = await store.record(for: scope.key(for: .camera))?.decision.state
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(storedCameraState, .allow)
    }

    func testUnsupportedContentNoteCleanupToggleAndResetScope() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let scope = SumiPermissionSiteScope(
            profilePartitionId: harness.profile.id.uuidString,
            isEphemeralProfile: false,
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            displayDomain: "example.com"
        )
        await harness.coordinator.seed(key: scope.key(for: .camera), state: .allow)
        harness.websiteDataService.entries = [
            SumiSiteDataEntry(domain: "example.com", cookieCount: 3, recordCount: 2),
        ]

        let rootSource = try sourceFile("Sumi/Permissions/UI/SumiSiteSettingsView.swift")
        XCTAssertTrue(rootSource.contains("unsupportedSection"))
        XCTAssertTrue(rootSource.contains("SumiSiteSettingsStrings.unsupportedContentCopy"))
        XCTAssertFalse(rootSource.contains("case javascript"))
        XCTAssertFalse(rootSource.contains("case images"))

        let viewModel = SumiSiteSettingsViewModel(repository: harness.repository)
        await viewModel.load(profile: harness.profile)
        XCTAssertFalse(viewModel.cleanupSettings.isAutomaticCleanupEnabled)

        await viewModel.setAutomaticCleanupEnabled(true, profile: harness.profile)
        let cameraBeforeReset = await harness.coordinator.record(for: scope.key(for: .camera))
        XCTAssertTrue(viewModel.cleanupSettings.isAutomaticCleanupEnabled)
        XCTAssertNotNil(cameraBeforeReset)
        XCTAssertTrue(harness.websiteDataService.exactHostRemovals.isEmpty)

        let detail = SumiSiteSettingsSiteDetailViewModel(scope: scope, repository: harness.repository)
        await detail.load(profile: harness.profile)
        await detail.resetPermissions()

        let cameraAfterReset = await harness.coordinator.record(for: scope.key(for: .camera))
        XCTAssertNil(cameraAfterReset)
        XCTAssertTrue(harness.websiteDataService.exactHostRemovals.isEmpty)
    }

    private var profileContext: SumiPermissionSettingsProfileContext {
        SumiPermissionSettingsProfileContext(
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            profileName: "Work"
        )
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
