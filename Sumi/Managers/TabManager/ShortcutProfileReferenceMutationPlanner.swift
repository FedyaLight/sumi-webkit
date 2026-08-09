import Foundation
import SumiDomain

/// Pure snapshot-to-plan projection for references that are safe to mutate
/// only after every WebView transition commits.
@MainActor
struct ShortcutProfileReferenceMutationPlanner {
    func plan(
        deleting profileID: UUID,
        fallbackProfileID: UUID,
        state: ShortcutPinCollectionStateOwner,
        splitGroups: [SplitGroup]
    ) -> ShortcutProfileReferenceMutationPlan? {
        let profileSnapshot = state.pinnedByProfileSnapshot()
        let pendingPins = state.pendingPinnedWithoutProfileSnapshot()
        var profileReplacements: [UUID: [ShortcutPin]] = [:]
        for (ownerProfileID, pins) in profileSnapshot
        where ownerProfileID != profileID {
            let replacement = migratePins(
                pins,
                deleting: profileID,
                ownerProfileID: ownerProfileID
            )
            if !sameObjects(pins, replacement) {
                profileReplacements[ownerProfileID] = replacement
            }
        }

        if pendingPins.isEmpty == false {
            let destination = profileReplacements[fallbackProfileID]
                ?? profileSnapshot[fallbackProfileID, default: []]
            let migratedPending = migratePins(
                pendingPins,
                deleting: profileID,
                ownerProfileID: fallbackProfileID,
                forceOwnerProfile: true
            )
            let combined = destination + migratedPending
            guard Set(combined.map(\.id)).count == combined.count else {
                return nil
            }
            profileReplacements[fallbackProfileID] = ShortcutPin.reindexed(
                combined
            )
        }

        let spaceSnapshot = state.spacePinnedShortcutsSnapshot()
        var spaceReplacements: [UUID: [ShortcutPin]] = [:]
        for (spaceID, pins) in spaceSnapshot {
            let replacement = migratePins(
                pins,
                deleting: profileID,
                ownerProfileID: nil
            )
            if !sameObjects(pins, replacement) {
                spaceReplacements[spaceID] = replacement
            }
        }

        let removedPinIDs = Set(
            profileSnapshot[profileID, default: []].map(\.id)
        )
        let groupsAfterPinRemoval = ShortcutLiveRetirementSplitProjection
            .removingDeletedPins(removedPinIDs, from: splitGroups)
        let migratedGroups = groupsAfterPinRemoval.compactMap {
            migrateSplitGroup(
                $0,
                deleting: profileID,
                fallbackProfileID: fallbackProfileID
            )
        }
        guard migratedGroups.count == groupsAfterPinRemoval.count else {
            return nil
        }
        let splitReplacement = migratedGroups == splitGroups
            ? nil
            : ShortcutProfileReferenceMutationPlan.SplitReplacement(
                expected: splitGroups,
                replacement: migratedGroups
            )
        let migratedSplitReference = groupsAfterPinRemoval != migratedGroups

        return ShortcutProfileReferenceMutationPlan(
            deletedProfileID: profileID,
            fallbackProfileID: fallbackProfileID,
            removedProfilePins: profileSnapshot[profileID],
            profilePinReplacements: profileReplacements,
            spacePinReplacements: spaceReplacements,
            pendingPinsToAdopt: pendingPins,
            splitReplacement: splitReplacement,
            requiresFallbackAdmission: pendingPins.isEmpty == false
                || migratedSplitReference
        )
    }

    private func migratePins(
        _ pins: [ShortcutPin],
        deleting profileID: UUID,
        ownerProfileID: UUID?,
        forceOwnerProfile: Bool = false
    ) -> [ShortcutPin] {
        pins.map { pin in
            let profileReplacement: UUID?? = forceOwnerProfile
                || pin.profileId == profileID
                ? .some(ownerProfileID)
                : nil
            let executionReplacement: UUID?? = pin.executionProfileId
                == profileID ? .some(nil) : nil
            guard profileReplacement != nil || executionReplacement != nil else {
                return pin
            }
            return pin.updated(
                profileId: profileReplacement,
                executionProfileId: executionReplacement
            )
        }
    }

    private func migrateSplitGroup(
        _ group: SplitGroup,
        deleting profileID: UUID,
        fallbackProfileID: UUID
    ) -> SplitGroup? {
        let container: SplitGroupContainer
        switch group.container {
        case .regularTabs:
            container = group.container
        case .favoriteSidebar(let ownerProfileID, let index):
            container = .favoriteSidebar(
                profileId: ownerProfileID == profileID
                    ? fallbackProfileID : ownerProfileID,
                index: index
            )
        case .shortcutSidebar(
            let spaceID,
            let ownerProfileID,
            let folderID,
            let index
        ):
            container = .shortcutSidebar(
                spaceId: spaceID,
                profileId: ownerProfileID == profileID
                    ? fallbackProfileID : ownerProfileID,
                folderId: folderID,
                index: index
            )
        }
        guard let migrated = group.changingContainer(to: container) else {
            return nil
        }
        return migrated
    }

    private func sameObjects(
        _ lhs: [ShortcutPin],
        _ rhs: [ShortcutPin]
    ) -> Bool {
        lhs.count == rhs.count
            && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }
}
