import Foundation

/// Adapts the browser runtime to the focused profile-maintenance service at
/// the single settings command boundary. It owns no state or runtime graph.
@MainActor
enum BrowserProfileDeletionWorkflow {
    static func delete(_ profile: Profile, from browserRuntime: BrowserManager) {
        let currentProfileAuthority = browserRuntime.currentProfileAuthority
        SumiProfileMaintenanceService().deleteProfile(
            profile,
            using: SumiProfileMaintenanceService.Context(
                currentProfile: { [currentProfileAuthority] in
                    currentProfileAuthority.currentProfile
                },
                profileManager: browserRuntime.profileManager,
                migrateProfileReferences: { [weak browserRuntime] deleted, fallback in
                    guard let browserRuntime else { return .rejected }
                    return await browserRuntime.tabManager.profileAssignments
                        .deletion.migrate(
                            deletedProfileID: deleted,
                            fallbackProfileID: fallback
                        )
                },
                browsingDataCleanupService: browserRuntime.browsingDataCleanupService,
                websiteDataCleanupService: browserRuntime.dataServices.websiteDataCleanupService,
                faviconService: browserRuntime.dataServices.faviconService,
                visitedLinkStore: browserRuntime.dataServices.visitedLinkStore,
                permissionCleanupService: browserRuntime.permissionRuntime.permissionCleanupService,
                showNotice: { [weak browserRuntime] notice in
                    browserRuntime?.chromeBundle.nativeDialogPresentationOwner
                        .presentNoticeSheet(
                            BrowserNoticeSheetModel(
                                title: notice.title,
                                subtitle: notice.subtitle,
                                message: notice.message
                            ),
                            source: nil
                        )
                },
                switchToProfile: { [weak browserRuntime] profile in
                    await browserRuntime?.switchToProfile(profile)
                }
            )
        )
    }
}
