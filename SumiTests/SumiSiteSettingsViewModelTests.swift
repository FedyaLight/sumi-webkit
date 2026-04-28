import XCTest

@testable import Sumi

@MainActor
final class SumiSiteSettingsViewModelTests: XCTestCase {
    func testLoadsMainPageSectionsFromRepository() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        await harness.coordinator.seed(key: harness.key(.camera), state: .allow)
        harness.recentStore.recordSettingsChange(
            displayDomain: "example.com",
            key: harness.key(.camera),
            state: .allow
        )

        let viewModel = SumiSiteSettingsViewModel(repository: harness.repository)

        await viewModel.load(profile: harness.profile)

        XCTAssertEqual(viewModel.recentActivity.count, 1)
        XCTAssertEqual(viewModel.siteRows.count, 1)
        XCTAssertEqual(viewModel.categoryRows.map(\.category), SumiSiteSettingsPermissionCategory.allCases)
        XCTAssertTrue(viewModel.categoryRows.contains { $0.category == .camera && $0.exceptionCount == 1 })
    }

    func testSiteSearchFiltersByOrigin() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        await harness.coordinator.seed(key: harness.key(.camera), state: .allow)
        await harness.coordinator.seed(
            key: harness.key(
                .microphone,
                requestingOrigin: SumiPermissionOrigin(string: "https://media.example")
            ),
            state: .deny
        )
        let viewModel = SumiSiteSettingsViewModel(repository: harness.repository)
        await viewModel.load(profile: harness.profile)

        viewModel.searchText = "media"
        await viewModel.updateSearch(profile: harness.profile)

        XCTAssertEqual(viewModel.siteRows.map(\.scope.requestingOrigin.identity), ["https://media.example"])
    }

    func testUnsupportedContentSettingsAreNotPermissionCategories() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let viewModel = SumiSiteSettingsViewModel(repository: harness.repository)

        await viewModel.load(profile: harness.profile)

        let categoryIds = Set(viewModel.categoryRows.map(\.category.id))
        XCTAssertFalse(categoryIds.contains("javascript"))
        XCTAssertFalse(categoryIds.contains("images"))
        XCTAssertFalse(categoryIds.contains("automatic-downloads"))
        XCTAssertFalse(categoryIds.contains("ads"))
        XCTAssertFalse(categoryIds.contains("background-sync"))
        XCTAssertFalse(categoryIds.contains("sound"))
    }
}
