import Foundation

/// Migrates every live and persisted browser reference before a profile is
/// logically deleted. Interactive retirement and startup recovery share this
/// exact ordering.
@MainActor
final class BrowserProfileReferenceRetirementRuntime {
    private let tabs: ProfileDeletionMigration
    private let persistence: TabStructuralPersistenceService
    private let browserReferences: BrowserProfileReferenceRetirementCoordinator

    init(
        tabs: ProfileDeletionMigration,
        persistence: TabStructuralPersistenceService,
        browserReferences: BrowserProfileReferenceRetirementCoordinator
    ) {
        self.tabs = tabs
        self.persistence = persistence
        self.browserReferences = browserReferences
    }

    func migrateReferences(
        from deletedProfileID: UUID,
        to fallback: Profile
    ) async -> Bool {
        guard tabs.ensureFallbackSpace(for: fallback.id) else {
            return false
        }
        return await browserReferences.migrateReferences(
            from: deletedProfileID,
            to: fallback,
            migrateTabReferences: { [tabs, persistence] in
                guard await tabs.migrate(
                    deletedProfileID: deletedProfileID,
                    fallbackProfileID: fallback.id
                ) == .committed else {
                    return false
                }
                return await persistence
                    .persistPendingStructuralChangesAwaitingResult()
            }
        )
    }
}
