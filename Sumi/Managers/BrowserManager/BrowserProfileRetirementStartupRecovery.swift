import Foundation

@MainActor
enum BrowserProfileRetirementStartupRecovery {
    static func make(
        profileManager: ProfileManager,
        profileDeletion: ProfileDeletionMigration,
        tabPersistence: TabStructuralPersistenceService,
        referenceRetirement: BrowserProfileReferenceRetirementCoordinator,
        permissionRuntime: BrowserManagerPermissionRuntime,
        browsingDataCleanupService: SumiBrowsingDataCleanupService,
        cleanupDependencies: ProfileRetirementCleanupDependencies
    ) -> ProfileRetirementStartupRecovery {
        ProfileRetirementStartupRecovery(
            ledger: profileManager.profileReferenceAdmission,
            migrateReferences: { record in
                let fallback: Profile
                if let persistedFallback = profileManager.profiles.first(where: {
                    $0.id == record.fallbackProfileID
                }) {
                    fallback = persistedFallback
                } else if let recoveryFallback = profileManager.profiles.first,
                          try profileManager.profileReferenceAdmission
                              .retargetFallback(
                                  record.token,
                                  to: recoveryFallback.id
                              ) {
                    fallback = recoveryFallback
                } else {
                    throw ProfileRetirementStartupRecoveryError
                        .referenceMigrationFailed(
                            profileID: record.snapshot.id
                        )
                }
                guard await migrateReferences(
                    deletedProfileID: record.snapshot.id,
                    fallback: fallback,
                    profileDeletion: profileDeletion,
                    tabPersistence: tabPersistence,
                    referenceRetirement: referenceRetirement,
                    browsingDataCleanupService: browsingDataCleanupService
                ) else {
                    throw ProfileRetirementStartupRecoveryError
                        .referenceMigrationFailed(
                            profileID: record.snapshot.id
                        )
                }
            },
            prepareCleanup: { record in
                guard await permissionRuntime.prepareForProfileRetirement(
                    profilePartitionId: record.snapshot.id.uuidString
                ) else {
                    throw ProfileRetirementStartupRecoveryError
                        .cleanupPreparationFailed(
                            profileID: record.snapshot.id
                        )
                }
            },
            sanitizeDeferredReferences: { profileIDs in
                guard let defaultFallback = profileManager.profiles.first else {
                    return false
                }
                for profileID in profileIDs {
                    let record = profileManager.profileReferenceAdmission.records()
                        .first { $0.snapshot.id == profileID }
                    let fallback = record.flatMap { record in
                        profileManager.profiles.first {
                            $0.id == record.fallbackProfileID
                        }
                    } ?? defaultFallback
                    guard await migrateReferences(
                        deletedProfileID: profileID,
                        fallback: fallback,
                        profileDeletion: profileDeletion,
                        tabPersistence: tabPersistence,
                        referenceRetirement: referenceRetirement,
                        browsingDataCleanupService: browsingDataCleanupService
                    ) else {
                        return false
                    }
                }
                return true
            },
            cleanupFactory: { snapshot in
                ProfileRetirementCleanupComposition.make(
                    profile: Profile(
                        id: snapshot.id,
                        name: snapshot.name,
                        icon: snapshot.icon
                    ),
                    dependencies: cleanupDependencies
                )
            }
        )
    }

    private static func migrateReferences(
        deletedProfileID: UUID,
        fallback: Profile,
        profileDeletion: ProfileDeletionMigration,
        tabPersistence: TabStructuralPersistenceService,
        referenceRetirement: BrowserProfileReferenceRetirementCoordinator,
        browsingDataCleanupService: SumiBrowsingDataCleanupService
    ) async -> Bool {
        guard await browsingDataCleanupService
            .performDestructiveWebsiteDataCleanup(
                profileIDs: [deletedProfileID],
                deletion: {}
            )
        else { return false }
        guard await profileDeletion.migrate(
            deletedProfileID: deletedProfileID,
            fallbackProfileID: fallback.id
        ) == .committed else { return false }
        guard await tabPersistence.persistFullReconcileAwaitingResult(
            reason: "profile retirement recovery"
        ) else { return false }
        return await referenceRetirement.migrateReferences(
            from: deletedProfileID,
            to: fallback
        ) && referenceRetirement.containsReference(to: deletedProfileID) == false
    }
}
