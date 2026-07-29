import Foundation

/// Stable settings command backed by the exact profile-retirement authorities
/// assembled at browser startup.
@MainActor
final class BrowserProfileDeletionWorkflow {
    private let maintenanceService: SumiProfileMaintenanceService
    private let maintenanceContext: SumiProfileMaintenanceService.Context
    private weak var presenter: BrowserNativeDialogPresentationOwner?

    init(
        maintenanceService: SumiProfileMaintenanceService = .init(),
        maintenanceContext: SumiProfileMaintenanceService.Context,
        presenter: BrowserNativeDialogPresentationOwner
    ) {
        self.maintenanceService = maintenanceService
        self.maintenanceContext = maintenanceContext
        self.presenter = presenter
    }

    func requestDeletion(_ profile: Profile, message: String) {
        let resetsBrowserData =
            maintenanceContext.profileManager.profiles.count == 1
        presenter?.presentDestructiveConfirmationAlert(
            title: resetsBrowserData
                ? String(
                    localized: "Erase “\(profile.name)” and Reset?",
                    comment: "Last profile deletion confirmation title"
                )
                : String(
                    localized: "Delete “\(profile.name)”?",
                    comment: "Profile deletion confirmation title"
                ),
            message: resetsBrowserData
                ? String(
                    localized: "\(message)\n\nA new empty Default profile and Space will be created. Sumi settings and other browser-wide data will not be changed.",
                    comment: "Last profile deletion reset explanation"
                )
                : message,
            confirmButtonTitle: resetsBrowserData
                ? String(localized: "Erase and Reset")
                : String(localized: "Delete Profile"),
            onConfirm: { [weak self, weak profile] in
                guard let self, let profile else { return }
                self.delete(profile)
            }
        )
    }

    func delete(_ profile: Profile) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await maintenanceService.retireProfile(
                profile,
                using: maintenanceContext
            )
            present(result, for: profile)
        }
    }

    private func present(
        _ result: SumiProfileMaintenanceService.RetirementResult,
        for profile: Profile
    ) {
        switch result {
        case .completed:
            break
        case .failed(let message):
            presentNotice(
                title: String(localized: "Couldn't Delete Profile"),
                profile: profile,
                message: message
            )
        case .migrationPending:
            break
        case .cleanupPending:
            break
        }
    }

    private func presentNotice(
        title: String,
        profile: Profile,
        message: String
    ) {
        presenter?.presentNoticeAlert(
            title: title,
            subtitle: profile.name,
            message: message
        )
    }
}
