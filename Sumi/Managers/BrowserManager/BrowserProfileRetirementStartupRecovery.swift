import Foundation

@MainActor
enum BrowserProfileRetirementStartupRecovery {
    static func make(
        profileManager: ProfileManager,
        referenceMigration: BrowserProfileReferenceRetirementRuntime,
        permissionRuntime: BrowserManagerPermissionRuntime,
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
                guard await referenceMigration.migrateReferences(
                    from: record.snapshot.id,
                    to: fallback
                ) else {
                    throw ProfileRetirementStartupRecoveryError
                        .referenceMigrationFailed(
                            profileID: record.snapshot.id
                        )
                }
            },
            prepareRuntimeRetirement: { record in
                guard await permissionRuntime.prepareForProfileRetirement(
                    profilePartitionId: record.snapshot.id.uuidString
                ) else {
                    throw ProfileRetirementStartupRecoveryError
                        .cleanupPreparationFailed(
                            profileID: record.snapshot.id
                        )
                }
            },
            rehydrateRetirementState: { record in
                guard await permissionRuntime.rehydrateRetiredProfile(
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
                    guard await referenceMigration.migrateReferences(
                        from: profileID,
                        to: fallback
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
                        name: snapshot.name
                    ),
                    dependencies: cleanupDependencies
                )
            }
        )
    }
}
