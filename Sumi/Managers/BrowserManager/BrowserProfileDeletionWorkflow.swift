import Foundation

/// Stable settings command backed by the exact profile-retirement authorities
/// assembled at browser startup.
@MainActor
final class BrowserProfileDeletionWorkflow {
    private let maintenanceService: SumiProfileMaintenanceService
    private let maintenanceContext: SumiProfileMaintenanceService.Context

    init(
        maintenanceService: SumiProfileMaintenanceService = .init(),
        maintenanceContext: SumiProfileMaintenanceService.Context
    ) {
        self.maintenanceService = maintenanceService
        self.maintenanceContext = maintenanceContext
    }

    func delete(_ profile: Profile) {
        maintenanceService.deleteProfile(profile, using: maintenanceContext)
    }
}
