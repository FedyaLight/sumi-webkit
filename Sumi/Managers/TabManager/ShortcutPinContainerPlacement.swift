import Foundation
import SumiDomain

/// Places and removes a shortcut pin inside its owning container — the
/// profile's favorite list, a space's top-level pinned items, or a
/// space-pinned folder group. Callers above this role decide *whether* a
/// placement may happen; this role knows only *where* pins physically live.
@MainActor
final class ShortcutPinContainerPlacement {
    private let pins: ShortcutPinCollectionStateOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let spacePinnedStructure: SpacePinnedStructureOwner

    init(
        pins: ShortcutPinCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        spacePinnedStructure: SpacePinnedStructureOwner
    ) {
        self.pins = pins
        self.structuralMutations = structuralMutations
        self.spacePinnedStructure = spacePinnedStructure
    }

    /// Whether this exact pin instance is still the live catalog record.
    func isCanonical(_ pin: ShortcutPin) -> Bool {
        pins.shortcutPin(by: pin.id) === pin
    }

    func remove(_ pin: ShortcutPin) {
        switch pin.role {
        case .favorite:
            guard let profileID = pin.profileId else { return }
            let remaining = pins.favoritePins(for: profileID).filter {
                $0.id != pin.id
            }
            structuralMutations.setPinnedTabs(
                ShortcutPin.reindexed(remaining),
                for: profileID
            )
        case .spacePinned:
            guard let spaceID = pin.spaceId else { return }
            if pin.folderId == nil {
                let remaining = spacePinnedStructure
                    .topLevelSpacePinnedItems(for: spaceID).filter { item in
                        if case .shortcut(let existing) = item {
                            return existing.id != pin.id
                        }
                        return true
                    }
                spacePinnedStructure.applyTopLevelSpacePinnedOrder(
                    remaining,
                    for: spaceID
                )
            } else {
                spacePinnedStructure.withSpacePinnedShortcutGroup(
                    for: spaceID,
                    folderId: pin.folderId
                ) { $0.removeAll { $0.id == pin.id } }
            }
        }
    }

    /// Inserts the pin at `targetIndex`, refusing a Favorite insert that
    /// would exceed the stored-member capacity. Returns the live record.
    func insert(_ pin: ShortcutPin, at targetIndex: Int) -> ShortcutPin? {
        switch pin.role {
        case .favorite:
            guard let profileID = pin.profileId else { return nil }
            var destination = pins.favoritePins(for: profileID)
            destination.removeAll { $0.id == pin.id }
            guard destination.count
                    < FavoriteShortcutPlacementOwner.CapacityPolicy
                        .maxStoredMembers
            else { return nil }
            let safeIndex = max(0, min(targetIndex, destination.count))
            destination.insert(pin, at: safeIndex)
            let replacement = ShortcutPin.reindexed(destination)
            structuralMutations.setPinnedTabs(replacement, for: profileID)
            return replacement[safeIndex]
        case .spacePinned:
            guard let spaceID = pin.spaceId else { return nil }
            if pin.folderId == nil {
                guard let inserted = spacePinnedStructure.insertTopLevelSpacePinnedShortcut(
                    pin,
                    in: spaceID,
                    at: targetIndex
                ) else { return nil }
                return pins.spacePinnedPins(for: spaceID)
                    .first { $0.id == inserted.id }
            }
            spacePinnedStructure.withSpacePinnedShortcutGroup(
                for: spaceID,
                folderId: pin.folderId
            ) { destination in
                destination.removeAll { $0.id == pin.id }
                destination.insert(
                    pin,
                    at: max(0, min(targetIndex, destination.count))
                )
            }
            return pins.spacePinnedPins(for: spaceID)
                .first { $0.id == pin.id }
        }
    }

    /// Puts a pin back at its own recorded index after a failed move. Unlike
    /// `insert`, this bypasses capacity admission: the pin already held a slot.
    func restore(_ pin: ShortcutPin) {
        switch pin.role {
        case .favorite:
            guard let profileID = pin.profileId else { return }
            var destination = pins.favoritePins(for: profileID)
            destination.removeAll { $0.id == pin.id }
            destination.insert(
                pin,
                at: max(0, min(pin.index, destination.count))
            )
            structuralMutations.setPinnedTabs(
                ShortcutPin.reindexed(destination),
                for: profileID
            )
        case .spacePinned:
            guard let spaceID = pin.spaceId else { return }
            if pin.folderId == nil {
                _ = spacePinnedStructure.insertTopLevelSpacePinnedShortcut(
                    pin,
                    in: spaceID,
                    at: pin.index
                )
            } else {
                spacePinnedStructure.withSpacePinnedShortcutGroup(
                    for: spaceID,
                    folderId: pin.folderId
                ) { destination in
                    destination.removeAll { $0.id == pin.id }
                    destination.insert(
                        pin,
                        at: max(0, min(pin.index, destination.count))
                    )
                }
            }
        }
    }
}
