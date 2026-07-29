import Foundation

@MainActor
struct ProfileRetirementCleanupDependencies {
    let websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
    let faviconService: any BrowserFaviconServicing
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging
    let permissionCleanupService: SumiPermissionCleanupService
    let applicationDataCleanupService: ProfileApplicationDataCleanupService
}

enum ProfileRetirementCleanupCompositionError: Error {
    case persistentStoreRemovalFailed
}

@MainActor
enum ProfileRetirementCleanupComposition {
    static func make(
        profile: Profile,
        dependencies: ProfileRetirementCleanupDependencies
    ) -> ProfileDeletionCleanupOrchestrator {
        let removePersistentDataStore: @MainActor (UUID) async throws -> Void = {
            profileID in
            guard profile.id == profileID,
                  await profile.removePersistentDataStore(
                      cleanupService: dependencies.websiteDataCleanupService
                  )
            else {
                throw ProfileRetirementCleanupCompositionError
                    .persistentStoreRemovalFailed
            }
        }
        // The trailing checkpoint also resumes journals written before store
        // removal moved first; Profile suppresses a second WebKit call.
        return ProfileDeletionCleanupOrchestrator(participants: [
            BrowsingDataProfileCleanupParticipant(
                clearAllData: removePersistentDataStore
            ),
            ApplicationDataProfileCleanupParticipant { profileID in
                try await dependencies.applicationDataCleanupService.cleanup(
                    profileID: profileID
                )
            },
            FaviconProfileCleanupParticipant { profileID in
                guard profile.id == profileID else { return }
                try dependencies.faviconService.clearFaviconPartition(for: profile)
            },
            PermissionProfileCleanupParticipant { profileID in
                try await dependencies.permissionCleanupService.deleteAllDecisions(
                    profilePartitionId: profileID.uuidString
                )
            },
            VisitedLinksProfileCleanupParticipant { profileID in
                dependencies.visitedLinkStore.discardStore(for: profileID)
            },
            PersistentWebsiteDataStoreCleanupParticipant(
                removeDataStore: removePersistentDataStore
            ),
        ])
    }
}
