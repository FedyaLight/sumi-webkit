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
                guard let fallback = profileManager.profiles.first(where: {
                    $0.id == record.fallbackProfileID
                }) else {
                    throw ProfileRetirementStartupRecoveryError
                        .referenceMigrationFailed(
                            profileID: record.snapshot.id
                        )
                }
                let preflightAccepted = await browsingDataCleanupService
                    .performDestructiveWebsiteDataCleanup(
                        profileIDs: [record.snapshot.id],
                        deletion: {}
                    )
                guard preflightAccepted else {
                    throw ProfileRetirementStartupRecoveryError
                        .referenceMigrationFailed(
                            profileID: record.snapshot.id
                        )
                }
                let tabMigration = await profileDeletion.migrate(
                    deletedProfileID: record.snapshot.id,
                    fallbackProfileID: fallback.id
                )
                guard tabMigration == .committed,
                      await tabPersistence.persistFullReconcileAwaitingResult(
                          reason: "profile retirement recovery"
                      )
                else {
                    throw ProfileRetirementStartupRecoveryError
                        .referenceMigrationFailed(
                            profileID: record.snapshot.id
                        )
                }
                guard await referenceRetirement.migrateReferences(
                    from: record.snapshot.id,
                    to: fallback
                ), referenceRetirement.containsReference(
                    to: record.snapshot.id
                ) == false
                else {
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
}
