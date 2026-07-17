import Foundation

@MainActor
final class BrowserAutomaticPermissionCleanup {
    private let permissionRuntime: BrowserManagerPermissionRuntime
    private let dataServices: BrowserManagerDataServices

    init(
        permissionRuntime: BrowserManagerPermissionRuntime,
        dataServices: BrowserManagerDataServices
    ) {
        self.permissionRuntime = permissionRuntime
        self.dataServices = dataServices
    }

    @discardableResult
    func runIfNeeded(for profile: Profile?) async -> SumiPermissionCleanupResult? {
        guard let profile else { return nil }
        let repository = SumiPermissionSettingsRepository(
            permissionRuntime: permissionRuntime,
            dataServices: dataServices,
            autoplayStore: permissionRuntime.autoplayStore
        )
        return await repository.runAutomaticCleanupIfNeeded(
            profile: SumiPermissionSettingsProfileContext(profile: profile)
        )
    }
}
