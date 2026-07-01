import SwiftUI

/// Routes profile deletion through `SumiProfileMaintenanceService`,
/// owning the service instance.
@MainActor
final class BrowserProfileMaintenanceOwner {
    struct Dependencies {
        let makeMaintenanceContext: @MainActor () -> SumiProfileMaintenanceService.Context?
    }

    let profileMaintenanceService = SumiProfileMaintenanceService()
    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func deleteProfile(_ profile: Profile) {
        guard let context = dependencies.makeMaintenanceContext() else { return }
        profileMaintenanceService.deleteProfile(profile, using: context)
    }
}

extension BrowserProfileMaintenanceOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            makeMaintenanceContext: { [weak browserManager] in
                guard let browserManager else { return nil }
                return SumiProfileMaintenanceService.Context(
                    currentProfile: { [weak browserManager] in
                        browserManager?.currentProfile
                    },
                    profileManager: browserManager.profileManager,
                    tabManager: browserManager.tabManager,
                    browsingDataCleanupService: browserManager.browsingDataCleanupService,
                    websiteDataCleanupService: browserManager.dataServices.websiteDataCleanupService,
                    faviconService: browserManager.dataServices.faviconService,
                    visitedLinkStore: browserManager.dataServices.visitedLinkStore,
                    showNotice: { [weak browserManager] notice in
                        browserManager?.nativeDialogPresentationOwner.presentNoticeSheet(
                            BrowserNoticeSheetModel(
                                title: notice.title,
                                subtitle: notice.subtitle,
                                message: notice.message
                            ),
                            source: nil
                        )
                    },
                    switchToProfile: { [weak browserManager] profile in
                        await browserManager?.switchToProfile(profile)
                    }
                )
            }
        )
    }
}
