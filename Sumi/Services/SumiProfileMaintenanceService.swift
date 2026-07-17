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
        var persistProfileReferences: @MainActor () async -> Bool
        var migrateBrowserProfileReferences: @MainActor (
            UUID,
            Profile
        ) async -> Bool
        var hasProfileReferences: @MainActor (UUID) -> Bool
        var sealProfileRuntime: @MainActor (UUID) async -> Bool
        var browsingDataCleanupService: SumiBrowsingDataCleanupService
        var websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
        var faviconService: any BrowserFaviconServicing
        var visitedLinkStore: any BrowserVisitedLinkStoreManaging
        var permissionCleanupService: SumiPermissionCleanupService?
        var applicationDataCleanupService: ProfileApplicationDataCleanupService
        var showNotice: @MainActor (Notice) -> Void
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

            guard let cleanup = makeDeletionCleanupOrchestrator(
                for: profile,
                using: context
            ) else {
                showDeletionFailure(
                    profile,
                    message: "Required profile cleanup services are unavailable.",
                    using: context
                )
                return
            }

            let token: ProfileRetirementToken
            do {
                token = try context.profileManager.profileReferenceAdmission.reserve(
                    profile: profile,
                    fallbackID: replacement.id
                )
            } catch {
                showDeletionFailure(
                    profile,
                    message: "The profile could not be reserved for safe deletion.",
                    using: context
                )
                return
            }

            let preflightAccepted = await context.browsingDataCleanupService
                .performDestructiveWebsiteDataCleanup(
                    profileIDs: [profile.id],
                    deletion: {}
                )
            guard preflightAccepted else {
                cancelReservation(token, using: context)
                showDeletionFailure(
                    profile,
                    message: "The browser could not prepare profile data for safe deletion.",
                    using: context
                )
                return
            }

            do {
                guard try context.profileManager.beginReferenceMigration(token)
                else {
                    throw ProfileDeletionCleanupFailure.staleRetirement
                }
            } catch {
                cancelReservation(token, using: context)
                showDeletionFailure(
                    profile,
                    message: "The profile could not begin safe reference migration.",
                    using: context
                )
                return
            }

            let migration = await context.migrateProfileReferences(
                profile.id,
                replacement.id
            )
            guard migration == .committed else {
                showMigrationPending(profile, using: context)
                return
            }

            guard await context.persistProfileReferences() else {
                showMigrationPending(profile, using: context)
                return
            }

            guard await context.migrateBrowserProfileReferences(
                profile.id,
                replacement
            ) else {
                showMigrationPending(profile, using: context)
                return
            }

            guard context.currentProfile()?.id != profile.id,
                  context.hasProfileReferences(profile.id) == false,
                  context.profileManager.profileReferenceAdmission.validate(token)
            else {
                showMigrationPending(profile, using: context)
                return
            }

            do {
                guard try context.profileManager.commitLogicalDeletion(token) else {
                    showMigrationPending(profile, using: context)
                    return
                }
            } catch {
                showMigrationPending(profile, using: context)
                return
            }

            guard await context.sealProfileRuntime(profile.id) else {
                showCleanupPending(profile, using: context)
                return
            }

            do {
                guard try context.profileManager.profileReferenceAdmission
                    .beginCleaning(token) else {
                    throw ProfileDeletionCleanupFailure.staleRetirement
                }
            } catch {
                showCleanupPending(profile, using: context)
                return
            }

            do {
                guard let record = context.profileManager.profileReferenceAdmission
                    .record(for: token) else {
                    throw ProfileDeletionCleanupFailure.staleRetirement
                }
                try await cleanup.cleanup(
                    profileId: profile.id,
                    startingAt: record.nextCleanupStep,
                    checkpoint: { completedStep in
                        guard try context.profileManager.profileReferenceAdmission
                            .completeCleanupStep(
                                completedStep,
                                using: token
                            ) else {
                            throw ProfileDeletionCleanupFailure.staleRetirement
                        }
                    }
                )
                guard try context.profileManager.profileReferenceAdmission
                    .markRetired(token) else {
                    throw ProfileDeletionCleanupFailure.staleRetirement
                }
            } catch {
                showCleanupPending(profile, using: context)
            }
        }
    }

    /// Ordered cleanup participants for profile deletion (browsing data → favicons → permissions).
    private func makeDeletionCleanupOrchestrator(
        for profile: Profile,
        using context: Context
    ) -> ProfileDeletionCleanupOrchestrator? {
        guard let permissionCleanupService = context.permissionCleanupService else {
            return nil
        }
        return ProfileRetirementCleanupComposition.make(
            profile: profile,
            dependencies: ProfileRetirementCleanupDependencies(
                browsingDataCleanupService: context.browsingDataCleanupService,
                websiteDataCleanupService: context.websiteDataCleanupService,
                faviconService: context.faviconService,
                visitedLinkStore: context.visitedLinkStore,
                permissionCleanupService: permissionCleanupService,
                applicationDataCleanupService: context
                    .applicationDataCleanupService
            )
        )
    }

    private func cancelReservation(
        _ token: ProfileRetirementToken,
        using context: Context
    ) {
        do {
            _ = try context.profileManager.profileReferenceAdmission.cancel(token)
        } catch {
            RuntimeDiagnostics.emit(
                "[ProfileRetirement] Failed to cancel reservation: \(error)"
            )
        }
    }

    private func showDeletionFailure(
        _ profile: Profile,
        message: String,
        using context: Context
    ) {
        context.showNotice(
            Notice(
                title: "Couldn't Delete Profile",
                subtitle: profile.name,
                message: message
            )
        )
    }

    private func showCleanupPending(_ profile: Profile, using context: Context) {
        context.showNotice(
            Notice(
                title: "Profile Deleted",
                subtitle: profile.name,
                message: "Private data cleanup is pending and will resume automatically."
            )
        )
    }

    private func showMigrationPending(
        _ profile: Profile,
        using context: Context
    ) {
        context.showNotice(
            Notice(
                title: "Profile Deletion Pending",
                subtitle: profile.name,
                message: "Reference migration is pending and will resume automatically."
            )
        )
    }
}

private enum ProfileDeletionCleanupFailure: Error {
    case staleRetirement
}
