import Foundation

/// Deletes browser-owned, profile-keyed private data outside WebKit's data store.
/// Every operation must be idempotent because a later failure retries the whole step.
@MainActor
final class ProfileApplicationDataCleanupService {
    struct Operations {
        let clearHistory: @MainActor (UUID) async throws -> Void
        let clearBasicAuthCredentials: @MainActor (UUID) throws -> Void
        let clearSiteDataPolicies: @MainActor (UUID) throws -> Void
        let clearZoomPreferences: @MainActor (UUID) throws -> Void
        let clearBoosts: @MainActor (UUID) async throws -> Void
        let clearAdblockZapperRules: @MainActor (UUID) throws -> Void
        let clearExtensionPrivateData: @MainActor (UUID) throws -> Void
    }

    private let operations: Operations

    init(operations: Operations) {
        self.operations = operations
    }

    func cleanup(profileID: UUID) async throws {
        try await operations.clearHistory(profileID)
        try operations.clearBasicAuthCredentials(profileID)
        try operations.clearSiteDataPolicies(profileID)
        try operations.clearZoomPreferences(profileID)
        try await operations.clearBoosts(profileID)
        try operations.clearAdblockZapperRules(profileID)
        try operations.clearExtensionPrivateData(profileID)
    }
}

@MainActor
enum ProfileApplicationDataCleanupComposition {
    static func make(
        historyManager: HistoryManager,
        browsingDataCleanupService: SumiBrowsingDataCleanupService,
        siteDataPolicyStore: any BrowserSiteDataPolicyStoring,
        zoomManager: ZoomManager,
        boostsModule: SumiBoostsModule,
        adblockZapperStore: SumiAdblockZapperStore,
        extensionPreferences: UserDefaults
    ) -> ProfileApplicationDataCleanupService {
        ProfileApplicationDataCleanupService(
            operations: .init(
                clearHistory: { profileID in
                    await historyManager.flushPendingChanges()
                    _ = try await historyManager.store.clearAllExplicit(
                        profileId: profileID
                    )
                },
                clearBasicAuthCredentials: { profileID in
                    try browsingDataCleanupService
                        .deleteBasicAuthCredentialsForProfileRetirement(profileID)
                },
                clearSiteDataPolicies: { profileID in
                    try siteDataPolicyStore.deletePolicies(profileId: profileID)
                },
                clearZoomPreferences: { profileID in
                    try zoomManager.deletePreferences(profileID: profileID)
                },
                clearBoosts: { profileID in
                    try await boostsModule.deleteProfileData(profileID: profileID)
                },
                clearAdblockZapperRules: { profileID in
                    try adblockZapperStore.deleteProfileData(
                        profileID: profileID
                    )
                },
                clearExtensionPrivateData: { profileID in
                    try ExtensionProfilePrivateDataCleaner(
                        preferences: extensionPreferences
                    ).deleteProfileData(profileID: profileID)
                }
            )
        )
    }
}
