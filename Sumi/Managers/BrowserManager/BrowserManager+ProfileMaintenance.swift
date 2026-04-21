import SwiftUI

@MainActor
extension BrowserManager {
    func validateProfileIntegrity() {
        profileMaintenanceService.validateProfileIntegrity(
            using: makeProfileMaintenanceContext()
        )
    }

    func recoverFromProfileError(_ error: Error, profile: Profile?) {
        profileMaintenanceService.recoverFromProfileError(
            error,
            profile: profile,
            using: makeProfileMaintenanceContext()
        )
    }

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
            setCurrentProfile: { [weak self] profile in
                self?.currentProfile = profile
            },
            profileManager: profileManager,
            tabManager: tabManager,
            showNotice: { [weak self] notice in
                self?.presentProfileMaintenanceNotice(notice)
            },
            switchToProfile: { [weak self] profile in
                await self?.switchToProfile(profile)
            },
            switchToRecoveryProfile: { [weak self] profile in
                await self?.switchToProfile(profile, context: .recovery)
            }
        )
    }

    private func presentProfileMaintenanceNotice(
        _ notice: SumiProfileMaintenanceService.Notice
    ) {
        dialogManager.showDialog {
            StandardDialog(
                header: {
                    DialogHeader(
                        icon: notice.icon,
                        title: notice.title,
                        subtitle: notice.subtitle
                    )
                },
                content: {
                    Text(notice.message)
                        .font(.body)
                },
                footer: {
                    DialogFooter(rightButtons: [
                        DialogButton(text: "OK", variant: .primary) { [weak self] in
                            self?.closeDialog()
                        }
                    ])
                }
            )
        }
    }
}
