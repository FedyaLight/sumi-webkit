import Combine
import Foundation

@MainActor
final class SumiSiteSettingsSiteDetailViewModel: ObservableObject {
    @Published private(set) var detail: SumiSiteSettingsSiteDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var isResetting = false
    @Published private(set) var isDeletingData = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    let scope: SumiPermissionSiteScope
    private let repository: SumiPermissionSettingsRepository
    private(set) var profileContext: SumiPermissionSettingsProfileContext?
    private weak var profileObject: Profile?

    init(
        scope: SumiPermissionSiteScope,
        repository: SumiPermissionSettingsRepository
    ) {
        self.scope = scope
        self.repository = repository
    }

    func load(profile: Profile?) async {
        guard let profile else {
            detail = nil
            profileContext = nil
            profileObject = nil
            return
        }
        let context = SumiPermissionSettingsProfileContext(profile: profile)
        profileContext = context
        profileObject = profile
        isLoading = true
        defer { isLoading = false }

        do {
            detail = try await repository.siteDetail(
                scope: scope,
                profile: context,
                profileObject: profile
            )
            errorMessage = nil
        } catch {
            detail = nil
            errorMessage = error.localizedDescription
        }
    }

    func setOption(
        _ option: SumiCurrentSitePermissionOption,
        for row: SumiSiteSettingsPermissionRow
    ) async {
        do {
            try await repository.setOption(option, for: row)
            statusMessage = SumiSiteSettingsStrings.changesSaved
            errorMessage = nil
            await load(profile: profileObject)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetPermissions() async {
        guard let profileContext else { return }
        isResetting = true
        defer { isResetting = false }
        do {
            try await repository.resetSitePermissions(scope: scope, profile: profileContext)
            statusMessage = SumiSiteSettingsStrings.resetComplete
            errorMessage = nil
            await load(profile: profileObject)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteData() async {
        guard let profileObject else { return }
        isDeletingData = true
        defer { isDeletingData = false }
        await repository.deleteSiteData(scope: scope, profile: profileObject)
        statusMessage = SumiSiteSettingsStrings.dataDeleted
        await load(profile: profileObject)
    }

    func openSystemSettings(for row: SumiSiteSettingsPermissionRow) async {
        guard let kind = row.category?.systemKind else { return }
        _ = await repository.openSystemSettings(for: kind)
    }
}
