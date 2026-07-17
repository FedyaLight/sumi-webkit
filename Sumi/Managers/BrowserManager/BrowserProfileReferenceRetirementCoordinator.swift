import Foundation

/// Seals browser-shell profile references after the tab domain has completed
/// its own migration. It owns no profile, cleanup, or retirement-store state.
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
        to fallbackProfile: Profile
    ) async -> Bool {
        guard await preflight.prepare(
            deletedProfileID: deletedProfileID,
            fallbackProfile: fallbackProfile
        ) else { return false }

        return migration.migrate(
            from: deletedProfileID,
            to: fallbackProfile.id
        )
    }

    func containsReference(to profileID: UUID) -> Bool {
        inventory.containsReference(to: profileID)
    }
}
