import Foundation

@MainActor
struct ProfileRetirementCleanupDependencies {
    let browsingDataCleanupService: SumiBrowsingDataCleanupService
    let websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
    let faviconService: any BrowserFaviconServicing
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging
    let permissionCleanupService: SumiPermissionCleanupService
    let applicationDataCleanupService: ProfileApplicationDataCleanupService
}

enum ProfileRetirementCleanupCompositionError: Error {
    case websiteDataQuiesceFailed
    case persistentStoreRemovalFailed
}

@MainActor
enum ProfileRetirementCleanupComposition {
    static func make(
        profile: Profile,
        dependencies: ProfileRetirementCleanupDependencies
    ) -> ProfileDeletionCleanupOrchestrator {
        ProfileDeletionCleanupOrchestrator(participants: [
            BrowsingDataProfileCleanupParticipant { profileID in
                guard profile.id == profileID,
                      await profile.clearAllData(
                          browsingDataCleanupService: dependencies
                              .browsingDataCleanupService,
                          websiteDataCleanupService: dependencies
                              .websiteDataCleanupService
                      )
                else {
                    throw ProfileRetirementCleanupCompositionError
                        .websiteDataQuiesceFailed
                }
            },
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
            PersistentWebsiteDataStoreCleanupParticipant { profileID in
                guard profile.id == profileID,
                      await profile.removePersistentDataStore(
                          cleanupService: dependencies.websiteDataCleanupService
                      )
                else {
                    throw ProfileRetirementCleanupCompositionError
                        .persistentStoreRemovalFailed
                }
            },
        ])
    }
}
