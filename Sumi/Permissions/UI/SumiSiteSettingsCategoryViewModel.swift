import Combine
import Foundation

@MainActor
final class SumiSiteSettingsCategoryViewModel: ObservableObject {
    @Published private(set) var detail: SumiSiteSettingsCategoryDetail?
    @Published private(set) var isLoading = false
    @Published var searchText = ""
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    let category: SumiSiteSettingsPermissionCategory
    private let repository: SumiPermissionSettingsRepository
    private(set) var profileContext: SumiPermissionSettingsProfileContext?

    init(
        category: SumiSiteSettingsPermissionCategory,
        repository: SumiPermissionSettingsRepository
    ) {
        self.category = category
        self.repository = repository
    }

    func load(profile: Profile?) async {
        guard let profile else {
            detail = nil
            profileContext = nil
            return
        }
        let context = SumiPermissionSettingsProfileContext(profile: profile)
        profileContext = context
        await load(context: context)
    }

    func reload() async {
        guard let profileContext else { return }
        await load(context: profileContext)
    }

    func setOption(
        _ option: SumiCurrentSitePermissionOption,
        for row: SumiSiteSettingsPermissionRow
    ) async {
        do {
            try await repository.setOption(option, for: row)
            statusMessage = SumiSiteSettingsStrings.changesSaved
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeException(_ row: SumiSiteSettingsPermissionRow) async {
        do {
            try await repository.removeException(for: row)
            statusMessage = SumiSiteSettingsStrings.resetComplete
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openSystemSettings() async {
        guard let kind = category.systemKind else { return }
        _ = await repository.openSystemSettings(for: kind)
    }

    private func load(context: SumiPermissionSettingsProfileContext) async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await repository.categoryDetail(
                category: category,
                profile: context,
                searchText: searchText
            )
            errorMessage = nil
        } catch {
            detail = nil
            errorMessage = error.localizedDescription
        }
    }
}
