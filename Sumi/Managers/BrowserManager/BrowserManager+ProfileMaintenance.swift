import SwiftUI

@MainActor
extension BrowserManager {
    func deleteProfile(_ profile: Profile) {
        profileMaintenanceService.deleteProfile(
            profile,
            using: makeProfileMaintenanceContext()
        )
    }

    private func makeProfileMaintenanceContext() -> SumiProfileMaintenanceService.Context {
        SumiProfileMaintenanceService.Context(
            currentProfile: { [weak self] in
                self?.currentProfile
            },
            profileManager: profileManager,
            tabManager: tabManager,
            showNotice: { [weak self] notice in
                self?.presentProfileMaintenanceNotice(notice)
            },
            switchToProfile: { [weak self] profile in
                await self?.switchToProfile(profile)
            }
        )
    }

    private func presentProfileMaintenanceNotice(
        _ notice: SumiProfileMaintenanceService.Notice
    ) {
        presentNoticeSheet(
            BrowserNoticeSheetModel(
                icon: notice.icon,
                title: notice.title,
                subtitle: notice.subtitle,
                message: notice.message
            )
        )
    }
}
