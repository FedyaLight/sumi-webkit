import XCTest

@testable import Sumi

@MainActor
final class SumiSiteSettingsCategoryViewModelTests: XCTestCase {
    func testCategoryListsOnlyMatchingPermissionExceptions() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        await harness.coordinator.seed(key: harness.key(.camera), state: .allow)
        await harness.coordinator.seed(key: harness.key(.microphone), state: .deny)

        let viewModel = SumiSiteSettingsCategoryViewModel(
            category: .camera,
            repository: harness.repository
        )

        await viewModel.load(profile: harness.profile)

        XCTAssertEqual(viewModel.detail?.rows.map(\.title), ["Camera"])
        XCTAssertEqual(viewModel.detail?.rows.first?.currentOption, .allow)
    }

    func testCategorySearchFiltersSiteExceptions() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        await harness.coordinator.seed(key: harness.key(.camera), state: .allow)
        await harness.coordinator.seed(
            key: harness.key(
                .camera,
                requestingOrigin: SumiPermissionOrigin(string: "https://media.example")
            ),
            state: .deny
        )
        let viewModel = SumiSiteSettingsCategoryViewModel(
            category: .camera,
            repository: harness.repository
        )

        await viewModel.load(profile: harness.profile)
        viewModel.searchText = "media"
        await viewModel.reload()

        XCTAssertEqual(viewModel.detail?.rows.map(\.scope.requestingOrigin.identity), ["https://media.example"])
    }

    func testRemoveSiteExceptionClearsOnlyThatPermission() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let camera = harness.key(.camera)
        let microphone = harness.key(.microphone)
        await harness.coordinator.seed(key: camera, state: .allow)
        await harness.coordinator.seed(key: microphone, state: .deny)
        let viewModel = SumiSiteSettingsCategoryViewModel(
            category: .camera,
            repository: harness.repository
        )
        await viewModel.load(profile: harness.profile)
        let row = try XCTUnwrap(viewModel.detail?.rows.first)

        await viewModel.removeException(row)

        let cameraRecord = await harness.coordinator.record(for: camera)
        let microphoneRecord = await harness.coordinator.record(for: microphone)
        XCTAssertNil(cameraRecord)
        XCTAssertNotNil(microphoneRecord)
    }

    func testSystemStatusIsSeparateFromSiteDecision() async throws {
        let system = SiteSettingsFakeSystemPermissionService(states: [.camera: .denied])
        let harness = try SiteSettingsRepositoryHarness(system: system)
        let viewModel = SumiSiteSettingsCategoryViewModel(
            category: .camera,
            repository: harness.repository
        )

        await viewModel.load(profile: harness.profile)

        XCTAssertEqual(viewModel.detail?.systemSnapshot?.state, .denied)
        let records = try await harness.repository.permissionRecords(profile: harness.profileContext)
        XCTAssertTrue(records.isEmpty)
    }
}
