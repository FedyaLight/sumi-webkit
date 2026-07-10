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
        var migrateProfileReferences: @MainActor (
            UUID,
            UUID
        ) async -> ProfileDeletionMigrationOutcome
        var browsingDataCleanupService: SumiBrowsingDataCleanupService
        var websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
        var faviconService: any BrowserFaviconServicing
        var visitedLinkStore: any BrowserVisitedLinkStoreManaging
        var permissionCleanupService: SumiPermissionCleanupService?
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

            let migration = await context.migrateProfileReferences(
                profile.id,
                replacement.id
            )
            guard migration == .committed else {
                context.showNotice(
                    Notice(
                        title: "Couldn't Delete Profile",
                        subtitle: profile.name,
                        message: "Open tabs could not be migrated safely. Please try again."
                    )
                )
                return
            }

            if context.currentProfile()?.id == profile.id {
                await context.switchToProfile(replacement)
                guard context.currentProfile()?.id != profile.id else {
                    context.showNotice(
                        Notice(
                            title: "Couldn't Delete Profile",
                            subtitle: profile.name,
                            message: "The browser could not leave this profile safely. Please try again."
                        )
                    )
                    return
                }
            }

            do {
                try await makeDeletionCleanupOrchestrator(for: profile, using: context)
                    .cleanup(profileId: profile.id)
            } catch {
                context.showNotice(
                    Notice(
                        title: "Couldn't Delete Profile",
                        subtitle: profile.name,
                        message: "Cleanup failed before deletion. Please try again."
                    )
                )
                return
            }

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

    /// Ordered cleanup participants for profile deletion (browsing data → favicons → permissions).
    private func makeDeletionCleanupOrchestrator(
        for profile: Profile,
        using context: Context
    ) -> ProfileDeletionCleanupOrchestrator {
        var participants: [any ProfileCleanupParticipant] = [
            BrowsingDataProfileCleanupParticipant { profileId in
                guard profile.id == profileId else { return }
                guard await profile.clearAllData(
                    browsingDataCleanupService: context.browsingDataCleanupService,
                    websiteDataCleanupService: context.websiteDataCleanupService
                ) else {
                    throw ProfileDeletionCleanupError.websiteDataQuiesceFailed
                }
            },
            FaviconProfileCleanupParticipant { profileId in
                guard profile.id == profileId else { return }
                context.faviconService.clearFaviconPartition(for: profile)
            },
        ]

        if let permissionCleanupService = context.permissionCleanupService {
            participants.append(
                PermissionProfileCleanupParticipant { profileId in
                    try await permissionCleanupService.deleteAllDecisions(
                        profilePartitionId: profileId.uuidString
                    )
                }
            )
        } else {
            participants.append(StubProfileCleanupParticipant(name: "permissions"))
        }

        return ProfileDeletionCleanupOrchestrator(participants: participants)
    }
}

private enum ProfileDeletionCleanupError: Error {
    case websiteDataQuiesceFailed
}
