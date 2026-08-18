import Foundation

/// Reclaims abandoned WebExtension controller namespaces in bounded batches.
/// The Browser Database is the authority for live profile namespaces.
@available(macOS 15.5, *)
@MainActor
enum SumiOrphanWebExtensionControllerReclaimer {
    private static let documentKey =
        "local-installation-storage.web-extension-controller-orphans.v1"
    private static let batchSize = 16

    @discardableResult
    static func runIfNeeded(
        liveControllerIDs: Set<UUID>,
        database: SumiDatabase,
        fetchIdentifiers: () -> [UUID],
        removeIdentifier: (UUID) -> Bool
    ) async throws -> [UUID] {
        try await SumiOrphanIdentifierBatch.runIfNeeded(
            documentKey: documentKey,
            batchSize: batchSize,
            liveIdentifiers: liveControllerIDs,
            database: database,
            fetchIdentifiers: { fetchIdentifiers() },
            removeIdentifier: { removeIdentifier($0) }
        )
    }

    static func liveControllerIdentifiers(
        database: SumiDatabase
    ) throws -> Set<UUID> {
        let profileIDs = try database.read { connection in
            try connection.profiles.all().map(\.id)
        }
        return Set(profileIDs.map {
            ExtensionProfileControllerIdentity.persistentIdentifier(for: $0)
        })
    }
}
