import Foundation

@MainActor
final class SumiProfileMaintenanceService {
    enum RetirementResult: Equatable {
        case completed
        case failed(String)
        case migrationPending
        case cleanupPending
    }

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
            guard let replacement = context.profileManager.profiles.first(where: {
                $0.id != profile.id
            }) else { return }
            switch await retireProfile(
                profile,
                fallback: replacement,
                using: context
            ) {
            case .completed:
                break
            case .failed(let message):
                showDeletionFailure(profile, message: message, using: context)
            case .migrationPending:
                showMigrationPending(profile, using: context)
            case .cleanupPending:
                showCleanupPending(profile, using: context)
            }
        }
    }

    func retireProfile(
        _ profile: Profile,
        fallback replacement: Profile,
        using context: Context
    ) async -> RetirementResult {
        guard profile.id != replacement.id,
              context.profileManager.profiles.contains(where: { $0.id == profile.id }),
              context.profileManager.profiles.contains(where: { $0.id == replacement.id })
        else {
            return .failed("The profile or its replacement is unavailable.")
        }
        guard let cleanup = makeDeletionCleanupOrchestrator(
            for: profile,
            using: context
        ) else {
            return .failed("Required profile cleanup services are unavailable.")
        }

        let token: ProfileRetirementToken
        do {
            token = try context.profileManager.profileReferenceAdmission.reserve(
                profile: profile,
                fallbackID: replacement.id
            )
        } catch {
            return .failed("The profile could not be reserved for safe deletion.")
        }

        let preflightAccepted = await context.browsingDataCleanupService
            .performDestructiveWebsiteDataCleanup(
                profileIDs: [profile.id],
                deletion: { /* Cleanup runs after logical deletion. */ }
            )
        guard preflightAccepted else {
            cancelReservation(token, using: context)
            return .failed("The browser could not prepare profile data for safe deletion.")
        }

        do {
            guard try context.profileManager.beginReferenceMigration(token) else {
                throw ProfileDeletionCleanupFailure.staleRetirement
            }
        } catch {
            cancelReservation(token, using: context)
            return .failed("The profile could not begin safe reference migration.")
        }

        let migration = await context.migrateProfileReferences(
            profile.id,
            replacement.id
        )
        guard migration == .committed,
              await context.persistProfileReferences(),
              await context.migrateBrowserProfileReferences(
                  profile.id,
                  replacement
              ),
              context.currentProfile()?.id != profile.id,
              context.hasProfileReferences(profile.id) == false,
              context.profileManager.profileReferenceAdmission.validate(token)
        else {
            return .migrationPending
        }

        do {
            guard try context.profileManager.commitLogicalDeletion(token) else {
                return .migrationPending
            }
        } catch {
            return .migrationPending
        }

        guard await context.sealProfileRuntime(profile.id) else {
            return .cleanupPending
        }

        return await completeRetirementCleanup(
            profile,
            token: token,
            cleanup: cleanup,
            using: context
        )
    }

    private func completeRetirementCleanup(
        _ profile: Profile,
        token: ProfileRetirementToken,
        cleanup: ProfileDeletionCleanupOrchestrator,
        using context: Context
    ) async -> RetirementResult {
        do {
            guard try context.profileManager.profileReferenceAdmission
                .beginCleaning(token),
                  let record = context.profileManager.profileReferenceAdmission
                    .record(for: token)
            else {
                throw ProfileDeletionCleanupFailure.staleRetirement
            }
            try await cleanup.cleanup(
                profileId: profile.id,
                startingAt: record.nextCleanupStep,
                checkpoint: { completedStep in
                    guard try context.profileManager.profileReferenceAdmission
                        .completeCleanupStep(completedStep, using: token) else {
                        throw ProfileDeletionCleanupFailure.staleRetirement
                    }
                }
            )
            guard try context.profileManager.profileReferenceAdmission
                .markRetired(token) else {
                throw ProfileDeletionCleanupFailure.staleRetirement
            }
            return .completed
        } catch {
            return .cleanupPending
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
