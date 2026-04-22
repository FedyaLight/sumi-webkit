import Foundation

@MainActor
final class SumiProfileMaintenanceService {
    struct Notice {
        var icon: String
        var title: String
        var subtitle: String
        var message: String
    }

    struct Context {
        var currentProfile: @MainActor () -> Profile?
        var profileManager: ProfileManager
        var tabManager: TabManager
        var showNotice: @MainActor (Notice) -> Void
        var switchToProfile: @MainActor (Profile) async -> Void
    }

    func deleteProfile(_ profile: Profile, using context: Context) {
        guard context.profileManager.profiles.count > 1 else {
            context.showNotice(
                Notice(
                    icon: "exclamationmark.triangle",
                    title: "Cannot Delete Last Profile",
                    subtitle: profile.name,
                    message: "At least one profile must remain."
                )
            )
            return
        }

        Task { @MainActor in
            if context.currentProfile()?.id == profile.id,
               let replacement = context.profileManager.profiles.first(where: { $0.id != profile.id })
            {
                await context.switchToProfile(replacement)
            }

            context.tabManager.cleanupProfileReferences(profile.id)
            await profile.clearAllData()

            let deleted = context.profileManager.deleteProfile(profile)
            if deleted == false {
                context.showNotice(
                    Notice(
                        icon: "exclamationmark.triangle",
                        title: "Couldn't Delete Profile",
                        subtitle: profile.name,
                        message: "An error occurred while saving changes. Please try again."
                    )
                )
            }
        }
    }
}
