import Combine
import Foundation

@MainActor
final class SumiSiteSettingsViewModel: ObservableObject {
    @Published private(set) var recentActivity: [SumiSiteSettingsRecentActivityItem] = []
    @Published private(set) var categoryRows: [SumiSiteSettingsCategoryRow] = []
    @Published private(set) var siteRows: [SumiSiteSettingsSiteRow] = []
    @Published private(set) var isLoading = false
    @Published private(set) var cleanupSettings = SumiPermissionCleanupSettings()
    @Published private(set) var cleanupStatusText: String?
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
            cleanupSettings = SumiPermissionCleanupSettings()
            cleanupStatusText = nil
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
            cleanupSettings = repository.cleanupSettings(profile: context)
            cleanupStatusText = Self.cleanupStatusText(cleanupSettings)
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
        cleanupSettings
    }

    func setAutomaticCleanupEnabled(_ isEnabled: Bool, profile: Profile?) async {
        guard let profile else { return }
        let context = SumiPermissionSettingsProfileContext(profile: profile)
        repository.setAutomaticCleanupEnabled(isEnabled, profile: context)
        cleanupSettings = repository.cleanupSettings(profile: context)
        cleanupStatusText = Self.cleanupStatusText(cleanupSettings)
        errorMessage = nil
    }

    private static func cleanupStatusText(
        _ settings: SumiPermissionCleanupSettings
    ) -> String? {
        guard let lastRunAt = settings.lastRunAt else { return nil }
        var parts = ["Last checked \(lastRunAt.formatted(date: .abbreviated, time: .shortened))"]
        if let lastRemovedCount = settings.lastRemovedCount {
            parts.append("\(lastRemovedCount) permission\(lastRemovedCount == 1 ? "" : "s") removed")
        }
        return parts.joined(separator: " | ")
    }
}
