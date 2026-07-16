import Foundation

struct ShortcutProfileReferenceMutationPlan {
    let deletedProfileID: UUID
    let removedProfilePins: [ShortcutPin]?
    let profilePinReplacements: [UUID: [ShortcutPin]]
    let spacePinReplacements: [UUID: [ShortcutPin]]

    var isEmpty: Bool {
        removedProfilePins == nil
            && profilePinReplacements.isEmpty
            && spacePinReplacements.isEmpty
    }
}

/// Pure snapshot-to-plan projection for references that are safe to mutate
/// only after every WebView transition commits.
@MainActor
struct ShortcutProfileReferenceMutationPlanner {
    func plan(
        deleting profileID: UUID,
        state: ShortcutPinCollectionStateOwner
    ) -> ShortcutProfileReferenceMutationPlan {
        let profileSnapshot = state.pinnedByProfileSnapshot()
        var profileReplacements: [UUID: [ShortcutPin]] = [:]
        for (ownerProfileID, pins) in profileSnapshot
            where ownerProfileID != profileID
                && pins.contains(where: { $0.executionProfileId == profileID }) {
            profileReplacements[ownerProfileID] = clearExecutionProfile(
                profileID,
                pins: pins
            )
        }

        let spaceSnapshot = state.spacePinnedShortcutsSnapshot()
        var spaceReplacements: [UUID: [ShortcutPin]] = [:]
        for (spaceID, pins) in spaceSnapshot
            where pins.contains(where: { $0.executionProfileId == profileID }) {
            spaceReplacements[spaceID] = clearExecutionProfile(
                profileID,
                pins: pins
            )
        }

        return ShortcutProfileReferenceMutationPlan(
            deletedProfileID: profileID,
            removedProfilePins: profileSnapshot[profileID],
            profilePinReplacements: profileReplacements,
            spacePinReplacements: spaceReplacements
        )
    }

    private func clearExecutionProfile(
        _ profileID: UUID,
        pins: [ShortcutPin]
    ) -> [ShortcutPin] {
        pins.map { pin in
            pin.executionProfileId == profileID
                ? pin.updated(executionProfileId: .some(nil))
                : pin
        }
    }
}

/// Applies an already-computed shortcut reference plan and owns its exact
/// persistence/publication effects.
@MainActor
final class ShortcutProfileReferenceMutationApplicator {
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let spacePinnedStructure: SpacePinnedStructureOwner
    private let persistence: TabStructuralPersistenceService
    private let runtimeConnection: TabRuntimePortConnection

    init(
        structuralMutations: TabStructuralCollectionMutationOwner,
        spacePinnedStructure: SpacePinnedStructureOwner,
        persistence: TabStructuralPersistenceService,
        runtimeConnection: TabRuntimePortConnection
    ) {
        self.structuralMutations = structuralMutations
        self.spacePinnedStructure = spacePinnedStructure
        self.persistence = persistence
        self.runtimeConnection = runtimeConnection
    }

    func apply(
        _ plan: ShortcutProfileReferenceMutationPlan,
        using runtimeLease: TabRuntimePortLease
    ) -> Bool {
        guard runtimeConnection.acceptsExactAttachment(runtimeLease) else {
            return false
        }
        guard !plan.isEmpty else { return true }
        guard let aggregate = structuralMutations.prepareAggregate() else {
            return false
        }

        if plan.removedProfilePins != nil {
            structuralMutations.removePinnedTabs(for: plan.deletedProfileID)
        }

        for profileID in plan.profilePinReplacements.keys.sorted(by: uuidOrder) {
            guard let pins = plan.profilePinReplacements[profileID] else {
                continue
            }
            structuralMutations.setPinnedTabs(
                ShortcutPin.reindexed(pins),
                for: profileID
            )
        }
        for spaceID in plan.spacePinReplacements.keys.sorted(by: uuidOrder) {
            guard let pins = plan.spacePinReplacements[spaceID] else { continue }
            structuralMutations.setSpacePinnedShortcuts(
                spacePinnedStructure.normalizedSpacePinnedShortcuts(pins),
                for: spaceID
            )
        }

        guard runtimeConnection.acceptsExactAttachment(runtimeLease),
              aggregate.stage(),
              runtimeConnection.acceptsExactAttachment(runtimeLease),
              aggregate.publish() else {
            _ = aggregate.rollback()
            return false
        }
        persistence.scheduleStructuralPersistence()
        return true
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
