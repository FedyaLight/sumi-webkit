import Foundation

@MainActor
final class SumiProfileMaintenanceService {
    struct Notice {
        var title: String
        var subtitle: String
        var message: String
    }

    struct Context {
        var currentProfile: @MainActor () -> Profile?
        var profileManager: ProfileManager
        var tabManager: TabManager
        var browsingDataCleanupService: SumiBrowsingDataCleanupService
        var websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
        var faviconService: any BrowserFaviconServicing
        var visitedLinkStore: any BrowserVisitedLinkStoreManaging
        var showNotice: @MainActor (Notice) -> Void
        var switchToProfile: @MainActor (Profile) async -> Void
    }

    func deleteProfile(_ profile: Profile, using context: Context) {
        guard context.profileManager.profiles.count > 1 else {
            context.showNotice(
                Notice(
                    title: "Cannot Delete Last Profile",
                    subtitle: profile.name,
                    message: "At least one profile must remain."
                )
            )
            return
        }

        Task { @MainActor in
            guard let replacement = context.profileManager.profiles.first(where: { $0.id != profile.id }) else {
                return
            }

            if context.currentProfile()?.id == profile.id {
                await context.switchToProfile(replacement)
            }

            context.tabManager.cleanupProfileReferences(
                profile.id,
                fallbackProfileId: replacement.id
            )
            await profile.clearAllData(
                browsingDataCleanupService: context.browsingDataCleanupService,
                websiteDataCleanupService: context.websiteDataCleanupService
            )
            context.faviconService.clearFaviconPartition(for: profile)

            let deleted = context.profileManager.deleteProfile(profile)
            if deleted == false {
                context.showNotice(
                    Notice(
                        title: "Couldn't Delete Profile",
                        subtitle: profile.name,
                        message: "An error occurred while saving changes. Please try again."
                    )
                )
            } else {
                _ = await profile.removePersistentDataStore(
                    cleanupService: context.websiteDataCleanupService
                )
                context.visitedLinkStore.discardStore(for: profile.id)
            }
        }
    }
}
