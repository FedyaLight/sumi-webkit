import Foundation

/// Prepares the browser runtime, lets the tab domain migrate, then seals every
/// browser-shell profile reference. It owns no profile, cleanup, or retirement
/// store state.
@MainActor
final class BrowserProfileReferenceRetirementCoordinator {
    private let preflight: BrowserProfileRetirementPreflight
    private let migration: BrowserProfileReferenceMigrationTransaction
    private let inventory: BrowserProfileReferenceInventory

    init(
        preflight: BrowserProfileRetirementPreflight,
        migration: BrowserProfileReferenceMigrationTransaction,
        inventory: BrowserProfileReferenceInventory
    ) {
        self.preflight = preflight
        self.migration = migration
        self.inventory = inventory
    }

    func migrateReferences(
        from deletedProfileID: UUID,
        to fallbackProfile: Profile,
        migrateTabReferences: @MainActor () async -> Bool = { true }
    ) async -> Bool {
        guard await preflight.prepare(
            deletedProfileID: deletedProfileID,
            fallbackProfile: fallbackProfile
        ), await migrateTabReferences() else {
            return false
        }

        return migration.migrate(
            from: deletedProfileID,
            to: fallbackProfile.id
        )
    }

    func containsReference(to profileID: UUID) -> Bool {
        inventory.containsReference(to: profileID)
    }
}
