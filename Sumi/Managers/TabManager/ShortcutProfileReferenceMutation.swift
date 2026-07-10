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
    private unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func apply(_ plan: ShortcutProfileReferenceMutationPlan) {
        guard !plan.isEmpty else { return }

        if let removedPins = plan.removedProfilePins {
            tabManager.objectWillChange.send()
            _ = tabManager.shortcutPinCollectionStateOwner.removePinnedPins(
                for: plan.deletedProfileID
            )
            tabManager.structuralPersistence.recordShortcutPinsStructuralChange(
                previous: removedPins,
                current: []
            )
            tabManager.structuralPersistence.markPinnedSnapshotDirty(
                for: plan.deletedProfileID
            )
        }

        for profileID in plan.profilePinReplacements.keys.sorted(by: uuidOrder) {
            guard let pins = plan.profilePinReplacements[profileID] else {
                continue
            }
            tabManager.structuralCollectionMutationOwner.setPinnedTabs(
                tabManager.shortcutPinStoreOwner.reindexed(pins),
                for: profileID
            )
        }
        for spaceID in plan.spacePinReplacements.keys.sorted(by: uuidOrder) {
            guard let pins = plan.spacePinReplacements[spaceID] else { continue }
            tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
                tabManager.spacePinnedStructureOwner
                    .normalizedSpacePinnedShortcuts(pins),
                for: spaceID
            )
        }

        tabManager.scheduleStructuralPersistence()
        tabManager.requestStructuralPublish()
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

@MainActor
final class ShortcutExecutionProfileAssignmentService {
    private unowned let tabManager: TabManager
    private let policy: ProfileAssignmentPolicy

    init(tabManager: TabManager, policy: ProfileAssignmentPolicy) {
        self.tabManager = tabManager
        self.policy = policy
    }

    @discardableResult
    func assign(
        _ pin: ShortcutPin,
        toExecutionProfile profileID: UUID
    ) -> ShortcutPin? {
        guard policy.profileExists(profileID) else {
            RuntimeDiagnostics.emit(
                "⚠️ [TabManager] Attempted to assign pinned tab to unknown profile: \(profileID)"
            )
            return nil
        }
        let current = tabManager.shortcutPinCollectionStateOwner.shortcutPin(
            by: pin.id
        ) ?? pin
        guard current.executionProfileId != profileID else { return current }
        return tabManager.shortcutPinCommandOwner.updateShortcutPin(
            current,
            executionProfileId: .some(profileID)
        )
    }
}
