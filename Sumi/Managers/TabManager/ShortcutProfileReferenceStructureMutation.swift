import Foundation
import SumiDomain

@MainActor
final class ShortcutProfileReferenceStructureMutation {
    private let pendingPins: PendingShortcutPinAdopter
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let spacePinnedStructure: SpacePinnedStructureOwner

    init(
        pendingPins: PendingShortcutPinAdopter,
        structuralMutations: TabStructuralCollectionMutationOwner,
        spacePinnedStructure: SpacePinnedStructureOwner
    ) {
        self.pendingPins = pendingPins
        self.structuralMutations = structuralMutations
        self.spacePinnedStructure = spacePinnedStructure
    }

    func prepareAggregate()
        -> TabStructuralCollectionMutationOwner.PreparedAggregate? {
        structuralMutations.prepareAggregate()
    }

    func apply(_ plan: ShortcutProfileReferenceMutationPlan) -> Bool {
        if plan.removedProfilePins != nil {
            structuralMutations.removePinnedTabs(for: plan.deletedProfileID)
        }
        for profileID in plan.profilePinReplacements.keys.sorted(by: uuidOrder) {
            guard let replacement = plan.profilePinReplacements[profileID] else {
                continue
            }
            structuralMutations.setPinnedTabs(replacement, for: profileID)
        }
        for spaceID in plan.spacePinReplacements.keys.sorted(by: uuidOrder) {
            guard let replacement = plan.spacePinReplacements[spaceID] else {
                continue
            }
            structuralMutations.setSpacePinnedShortcuts(
                spacePinnedStructure.normalizedSpacePinnedShortcuts(replacement),
                for: spaceID
            )
        }
        return plan.pendingPinsToAdopt.isEmpty || pendingPins.drainPendingPins(
            expecting: plan.pendingPinsToAdopt
        )
    }

    func schedulePersistence() {
        structuralMutations.schedulePersistence()
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
