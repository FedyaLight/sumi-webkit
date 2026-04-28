import XCTest

@testable import Sumi

@MainActor
final class SumiSiteSettingsSiteDetailViewModelTests: XCTestCase {
    func testSiteDetailIncludesImplementedPermissionRowsAndFilePickerOnlyWhenRecent() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let scope = siteScope(profile: harness.profile)
        harness.indicatorStore.record(
            SumiPermissionIndicatorEventRecord(
                tabId: "tab-a",
                pageId: "tab-a:1",
                displayDomain: "example.com",
                permissionTypes: [.filePicker],
                category: .pendingRequest,
                visualStyle: .attention,
                priority: .filePickerCurrentEvent,
                requestingOrigin: scope.requestingOrigin,
                topOrigin: scope.topOrigin,
                profilePartitionId: harness.profile.id.uuidString,
                isEphemeralProfile: false
            )
        )
        let viewModel = SumiSiteSettingsSiteDetailViewModel(
            scope: scope,
            repository: harness.repository
        )

        await viewModel.load(profile: harness.profile)

        let titles = viewModel.detail?.permissionRows.map(\.title) ?? []
        XCTAssertTrue(titles.contains("Location"))
        XCTAssertTrue(titles.contains("Camera"))
        XCTAssertTrue(titles.contains("Microphone"))
        XCTAssertTrue(titles.contains("Screen sharing"))
        XCTAssertTrue(titles.contains("Notifications"))
        XCTAssertTrue(titles.contains("Pop-ups and redirects"))
        XCTAssertTrue(titles.contains("External app links"))
        XCTAssertTrue(titles.contains("Autoplay"))
        XCTAssertTrue(titles.contains("Storage access"))
        XCTAssertNotNil(viewModel.detail?.filePickerRow)
    }

    func testChangingRowsWritesExpectedDecisions() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let scope = siteScope(profile: harness.profile)
        let viewModel = SumiSiteSettingsSiteDetailViewModel(
            scope: scope,
            repository: harness.repository
        )
        await viewModel.load(profile: harness.profile)
        let camera = try XCTUnwrap(viewModel.detail?.permissionRows.first { $0.title == "Camera" })
        let popups = try XCTUnwrap(viewModel.detail?.permissionRows.first { $0.title == "Pop-ups and redirects" })

        await viewModel.setOption(.allow, for: camera)
        await viewModel.setOption(.block, for: popups)

        let cameraRecord = await harness.coordinator.record(for: scope.key(for: .camera))
        let popupsRecord = await harness.coordinator.record(for: scope.key(for: .popups))
        XCTAssertEqual(cameraRecord?.decision.state, .allow)
        XCTAssertEqual(popupsRecord?.decision.state, .deny)
    }

    func testExternalSchemeAndAutoplayRemainIsolated() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let scope = siteScope(profile: harness.profile)
        let mailto = scope.key(for: .externalScheme("mailto"))
        let zoom = scope.key(for: .externalScheme("zoommtg"))
        await harness.coordinator.seed(key: mailto, state: .allow)
        await harness.coordinator.seed(key: zoom, state: .deny)
        let viewModel = SumiSiteSettingsSiteDetailViewModel(
            scope: scope,
            repository: harness.repository
        )
        await viewModel.load(profile: harness.profile)
        let mailtoRow = try XCTUnwrap(viewModel.detail?.permissionRows.first { $0.title == "mailto links" })
        let autoplayRow = try XCTUnwrap(viewModel.detail?.permissionRows.first { $0.kind == .autoplay })

        await viewModel.setOption(.block, for: mailtoRow)
        await viewModel.setOption(.allowAll, for: autoplayRow)

        let mailtoRecord = await harness.coordinator.record(for: mailto)
        let zoomRecord = await harness.coordinator.record(for: zoom)
        XCTAssertEqual(mailtoRecord?.decision.state, .deny)
        XCTAssertEqual(zoomRecord?.decision.state, .deny)
        XCTAssertEqual(harness.autoplayStore.explicitPolicy(for: scope.key(for: .autoplay)), .allowAll)
    }

    func testResetPermissionsDoesNotDeleteSiteData() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let scope = siteScope(profile: harness.profile)
        await harness.coordinator.seed(key: scope.key(for: .camera), state: .allow)
        harness.websiteDataService.entries = [
            SumiSiteDataEntry(domain: "example.com", cookieCount: 2, recordCount: 1),
        ]
        let viewModel = SumiSiteSettingsSiteDetailViewModel(
            scope: scope,
            repository: harness.repository
        )
        await viewModel.load(profile: harness.profile)

        await viewModel.resetPermissions()

        let cameraRecord = await harness.coordinator.record(for: scope.key(for: .camera))
        XCTAssertNil(cameraRecord)
        XCTAssertTrue(harness.websiteDataService.exactHostRemovals.isEmpty)
    }

    private func siteScope(profile: Profile) -> SumiPermissionSiteScope {
        SumiPermissionSiteScope(
            profilePartitionId: profile.id.uuidString,
            isEphemeralProfile: false,
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            displayDomain: "example.com"
        )
    }
}
