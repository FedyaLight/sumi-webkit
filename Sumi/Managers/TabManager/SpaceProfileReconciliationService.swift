import Foundation

@MainActor
final class SpaceProfileReconciliationService {
    private let spaces: TabSpaceCollectionStateOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let spaceTransitions: SpaceProfileTransitionService
    private let persistence: TabStructuralPersistenceService

    init(
        spaces: TabSpaceCollectionStateOwner,
        runtimeConnection: TabRuntimePortConnection,
        spaceTransitions: SpaceProfileTransitionService,
        persistence: TabStructuralPersistenceService
    ) {
        self.spaces = spaces
        self.runtimeConnection = runtimeConnection
        self.spaceTransitions = spaceTransitions
        self.persistence = persistence
    }

    func reconcileIfNeeded() {
        guard let profileID = runtimeConnection.current?.defaultProfileId else {
            RuntimeDiagnostics.debug(
                "No profiles available for space reconciliation yet.",
                category: "SpaceProfile"
            )
            return
        }

        var didAssign = false
        for space in spaces.spaces where space.profileId == nil {
            didAssign = spaceTransitions.assign(
                spaceID: space.id,
                toProfile: profileID
            ).wasAccepted || didAssign
        }
        guard didAssign else { return }
        persistence.markAllSpacesStructurallyDirty()
        persistence.scheduleStructuralPersistence()
    }
}
