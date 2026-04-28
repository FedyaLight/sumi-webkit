import Combine
import Foundation

@MainActor
final class SumiSiteSettingsViewModel: ObservableObject {
    @Published private(set) var recentActivity: [SumiSiteSettingsRecentActivityItem] = []
    @Published private(set) var categoryRows: [SumiSiteSettingsCategoryRow] = []
    @Published private(set) var siteRows: [SumiSiteSettingsSiteRow] = []
    @Published private(set) var isLoading = false
    @Published var searchText = ""
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    let repository: SumiPermissionSettingsRepository
    private(set) var profileContext: SumiPermissionSettingsProfileContext?

    init(repository: SumiPermissionSettingsRepository) {
        self.repository = repository
    }

    func load(profile: Profile?) async {
        guard let profile else {
            recentActivity = []
            categoryRows = []
            siteRows = []
            profileContext = nil
            return
        }

        let context = SumiPermissionSettingsProfileContext(profile: profile)
        profileContext = context
        isLoading = true
        defer { isLoading = false }

        do {
            recentActivity = repository.recentActivity(profile: context, limit: 6)
            categoryRows = try await repository.categoryRows(profile: context)
            siteRows = try await repository.siteRows(profile: context, searchText: searchText)
            errorMessage = nil
        } catch {
            recentActivity = []
            categoryRows = []
            siteRows = []
            errorMessage = error.localizedDescription
        }
    }

    func updateSearch(profile: Profile?) async {
        guard let profile else { return }
        let context = SumiPermissionSettingsProfileContext(profile: profile)
        do {
            siteRows = try await repository.siteRows(profile: context, searchText: searchText)
            errorMessage = nil
        } catch {
            siteRows = []
            errorMessage = error.localizedDescription
        }
    }

    func cleanupSettingsBinding() -> SumiPermissionCleanupSettings {
        repository.cleanupSettings
    }
}
