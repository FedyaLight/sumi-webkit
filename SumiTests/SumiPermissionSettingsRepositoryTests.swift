import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionSettingsRepositoryTests: XCTestCase {
    func testSiteRowsAreProfileScopedAndPreserveEmbeddedTopOrigin() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let embedded = SumiPermissionOrigin(string: "https://cdn.example")
        let top = SumiPermissionOrigin(string: "https://news.example")
        let otherProfile = Profile(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            name: "Other",
            icon: "person"
        )

        await harness.coordinator.seed(key: harness.key(.camera), state: .allow)
        await harness.coordinator.seed(
            key: harness.key(.microphone, requestingOrigin: embedded, topOrigin: top),
            state: .deny
        )
        await harness.coordinator.seed(
            key: harness.key(.geolocation, profile: otherProfile),
            state: .allow
        )

        let rows = try await harness.repository.siteRows(profile: harness.profileContext)

        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.contains { $0.scope.requestingOrigin.identity == "https://example.com" })
        let embeddedRow = try XCTUnwrap(rows.first { $0.scope.requestingOrigin.identity == embedded.identity })
        XCTAssertEqual(embeddedRow.scope.topOrigin.identity, top.identity)
        XCTAssertTrue(embeddedRow.subtitle.contains("embedded on"))
        XCTAssertFalse(rows.contains { $0.scope.profilePartitionId == otherProfile.id.uuidString.lowercased() })
    }

    func testSearchFiltersByDomainAndOrigin() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        await harness.coordinator.seed(key: harness.key(.camera), state: .allow)
        await harness.coordinator.seed(
            key: harness.key(
                .microphone,
                requestingOrigin: SumiPermissionOrigin(string: "https://media.example")
            ),
            state: .deny
        )

        let rows = try await harness.repository.siteRows(
            profile: harness.profileContext,
            searchText: "media"
        )

        XCTAssertEqual(rows.map(\.scope.requestingOrigin.identity), ["https://media.example"])
    }

    func testSetSiteDecisionAndRemoveExceptionUseCoordinatorOnlyForTargetPermission() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        await harness.coordinator.seed(key: harness.key(.camera), state: .ask)
        let scope = SumiPermissionSiteScope(
            profilePartitionId: harness.profile.id.uuidString,
            isEphemeralProfile: false,
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            displayDomain: "example.com"
        )
        let detail = try await harness.repository.siteDetail(
            scope: scope,
            profile: harness.profileContext,
            profileObject: harness.profile
        )
        let camera = try XCTUnwrap(detail.permissionRows.first { $0.title == "Camera" })

        try await harness.repository.setOption(.allow, for: camera)
        var record = await harness.coordinator.record(for: harness.key(.camera))
        XCTAssertEqual(record?.decision.state, .allow)

        try await harness.repository.removeException(for: camera)
        record = await harness.coordinator.record(for: harness.key(.camera))
        XCTAssertNil(record)
        let resetKeys = await harness.coordinator.resetKeys
        XCTAssertEqual(resetKeys.map(\.permissionType), [.camera])
    }

    func testResetSitePermissionsClearsOnlyExactScope() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let current = harness.key(.camera)
        let embedded = harness.key(
            .camera,
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://top.example")
        )
        await harness.coordinator.seed(key: current, state: .allow)
        await harness.coordinator.seed(key: embedded, state: .deny)

        let currentRecord = await harness.coordinator.record(for: current)
        let scope = SumiPermissionSiteScope(record: try XCTUnwrap(currentRecord))

        try await harness.repository.resetSitePermissions(scope: scope, profile: harness.profileContext)

        let resetRecord = await harness.coordinator.record(for: current)
        let embeddedRecord = await harness.coordinator.record(for: embedded)
        XCTAssertNil(resetRecord)
        XCTAssertNotNil(embeddedRecord)
    }

    func testAutoplayUsesCanonicalAdapterForExactKey() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let scope = SumiPermissionSiteScope(
            profilePartitionId: harness.profile.id.uuidString,
            isEphemeralProfile: false,
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            displayDomain: "example.com"
        )
        let detail = try await harness.repository.siteDetail(
            scope: scope,
            profile: harness.profileContext,
            profileObject: harness.profile
        )
        let autoplay = try XCTUnwrap(detail.permissionRows.first { $0.kind == .autoplay })

        try await harness.repository.setOption(.blockAudible, for: autoplay)

        XCTAssertEqual(harness.autoplayStore.explicitPolicy(for: scope.key(for: .autoplay)), .blockAudible)
        let coordinatorAutoplayRecord = await harness.coordinator.record(for: scope.key(for: .autoplay))
        XCTAssertNil(coordinatorAutoplayRecord)
    }

    func testCleanupPreferenceDoesNotDeletePermissions() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let key = harness.key(.camera)
        await harness.coordinator.seed(key: key, state: .allow)

        harness.repository.cleanupSettings = SumiPermissionCleanupSettings(isAutomaticCleanupEnabled: true)

        XCTAssertTrue(harness.repository.cleanupSettings.isAutomaticCleanupEnabled)
        let storedRecord = await harness.coordinator.record(for: key)
        XCTAssertNotNil(storedRecord)
        XCTAssertTrue(harness.websiteDataService.exactHostRemovals.isEmpty)
    }

    func testSourceLevelSettingsViewsAvoidForbiddenPermissionAPIs() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "Sumi/Components/Settings/PrivacySettingsView.swift",
            "Sumi/Permissions/UI/SumiSiteSettingsView.swift",
            "Sumi/Permissions/UI/SumiSiteSettingsCategoryView.swift",
            "Sumi/Permissions/UI/SumiSiteSettingsSiteDetailView.swift",
            "Sumi/Permissions/UI/SumiSiteSettingsRows.swift",
        ]
        let source = try paths.map {
            try String(contentsOf: repoRoot.appendingPathComponent($0), encoding: .utf8)
        }.joined(separator: "\n")

        XCTAssertFalse(source.contains("import SwiftData"))
        XCTAssertFalse(source.contains("requestAuthorization("))
        XCTAssertFalse(source.contains("WKPermission"))
        XCTAssertFalse(source.contains("WKUIDelegate"))
        XCTAssertFalse(source.contains("settings.sitePermissionOverrides.autoplay"))
        XCTAssertFalse(source.contains("case javascript"))
        XCTAssertFalse(source.contains("case images"))
        XCTAssertFalse(source.contains("case backgroundSync"))
    }
}
