import Foundation
import SumiWebRuntime


@MainActor
final class ProfileSpaceRetirementService {
    private let spaces: TabSpaceCollectionStateOwner
    private let creation: SpaceCreationTransaction
    private let removal: SpaceRemovalService
    private let transitions: SpaceProfileTransitionRepository

    init(
        spaces: TabSpaceCollectionStateOwner,
        creation: SpaceCreationTransaction,
        removal: SpaceRemovalService,
        transitions: SpaceProfileTransitionRepository
    ) {
        self.spaces = spaces
        self.creation = creation
        self.removal = removal
        self.transitions = transitions
    }

    func ensureFallbackSpace(for profileID: UUID) -> Bool {
        if spaces.spaces.contains(where: { $0.profileId == profileID }) {
            return true
        }
        return creation.create(
            id: UUID(),
            name: DefaultSpaceConfiguration.name,
            icon: DefaultSpaceConfiguration.icon,
            workspaceTheme: DefaultSpaceConfiguration.makeTheme(),
            profileID: profileID,
            referenceContext: .retirementMigration
        ) != nil
    }

    func retireSpaces(ownedBy profileID: UUID) -> Bool {
        guard transitions.containsReference(to: profileID) == false else {
            return false
        }
        let spaceIDs = spaces.spaces
            .filter { $0.profileId == profileID }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
        guard spaceIDs.isEmpty
                || removal.removeSpacesForProfileRetirement(spaceIDs) else {
            return false
        }
        return containsReference(to: profileID) == false
    }

    func containsReference(to profileID: UUID) -> Bool {
        spaces.spaces.contains { $0.profileId == profileID }
            || transitions.containsReference(to: profileID)
    }
}
