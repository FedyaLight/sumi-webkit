import Foundation

/// Best-effort safety net for Sumi-owned residue keyed by a private partition.
///
/// Prevention keeps new private state off disk. Cleanup therefore has no
/// durable checkpoint or caller that can honestly receive a failure after the
/// final private window has closed: every idempotent operation runs, failures
/// are diagnosed individually, and none are rethrown.
@MainActor
final class PrivatePartitionResidueCleanup: PrivatePartitionResidueCleaning {
    struct Operations {
        let clearSiteDataPolicies: @MainActor (UUID) throws -> Void
        let clearZoomPreferences: @MainActor (UUID) throws -> Void
        let discardAdblockZapperState: @MainActor (UUID) throws -> Void
        let clearExtensionPrivateData: @MainActor (UUID) throws -> Void
    }

    private let operations: Operations

    init(operations: Operations) {
        self.operations = operations
    }

    func cleanup(profileID: UUID) {
        run("site-data policies", profileID: profileID) {
            try operations.clearSiteDataPolicies(profileID)
        }
        run("zoom preferences", profileID: profileID) {
            try operations.clearZoomPreferences(profileID)
        }
        run("adblock zapper state", profileID: profileID) {
            try operations.discardAdblockZapperState(profileID)
        }
        run("extension private data", profileID: profileID) {
            try operations.clearExtensionPrivateData(profileID)
        }
    }

    private func run(
        _ domain: String,
        profileID: UUID,
        operation: () throws -> Void
    ) {
        do {
            try operation()
        } catch {
            RuntimeDiagnostics.emit(
                "[PrivatePartitionResidueCleanup] Failed to clear \(domain) for \(profileID.uuidString): \(error)"
            )
        }
    }
}

@MainActor
enum PrivatePartitionResidueCleanupComposition {
    static func make(
        siteDataPolicyStore: any BrowserSiteDataPolicyStoring,
        zoomManager: ZoomManager,
        adblockZapperStore: SumiAdblockZapperStore,
        database: SumiDatabase
    ) -> PrivatePartitionResidueCleanup {
        let extensionPrivateDataCleaner =
            ExtensionProfilePrivateDataCleaner(database: database)
        return PrivatePartitionResidueCleanup(
            operations: .init(
                clearSiteDataPolicies: {
                    try siteDataPolicyStore.deletePolicies(profileId: $0)
                },
                clearZoomPreferences: {
                    try zoomManager.deletePreferences(profileID: $0)
                },
                discardAdblockZapperState: {
                    adblockZapperStore.discardPrivatePartition(profileID: $0)
                },
                clearExtensionPrivateData: {
                    try extensionPrivateDataCleaner.deleteProfileData(
                        profileID: $0
                    )
                }
            )
        )
    }
}
