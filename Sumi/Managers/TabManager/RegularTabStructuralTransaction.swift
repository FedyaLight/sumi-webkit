import Foundation

/// Owns structural publication and persistence settlement for regular-tab
/// catalog mutations. Callers provide an already validated terminal model;
/// this role decides whether that model is a batched mutation or a persisted
/// user command.
@MainActor
final class RegularTabStructuralTransaction {
    private let mutations: TabStructuralCollectionMutationOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let persistence: TabStructuralPersistenceService

    init(
        mutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        persistence: TabStructuralPersistenceService
    ) {
        self.mutations = mutations
        self.structuralLookup = structuralLookup
        self.persistence = persistence
    }

    func replaceTabs(_ tabs: [Tab], in spaceID: UUID) {
        mutations.setTabs(tabs, for: spaceID)
    }

    func commitPersistedTabs(_ tabs: [Tab], in spaceID: UUID) {
        structuralLookup.withTransaction {
            mutations.setTabs(tabs, for: spaceID)
            persistence.scheduleStructuralPersistence()
        }
    }

    func commitPlacement(
        _ placement: PreparedRegularTabPlacement,
        removing source: @MainActor () -> Bool
    ) -> Bool {
        structuralLookup.withTransaction {
            mutations.withReversibleSideEffects {
                guard source() else {
                    _ = placement.cancel()
                    return false
                }
                return placement.commit()
            }
        }
    }
}
