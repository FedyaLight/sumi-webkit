import Foundation
import SumiDomain

@MainActor
final class ShortcutPinCatalogMutationTransaction {
    private let pins: ShortcutPinCollectionStateOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let spacePinnedStructure: SpacePinnedStructureOwner
    private let profileAdmissions: ProfileReferenceAdmissionLedger

    init(
        pins: ShortcutPinCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        spacePinnedStructure: SpacePinnedStructureOwner,
        profileAdmissions: ProfileReferenceAdmissionLedger
    ) {
        self.pins = pins
        self.structuralMutations = structuralMutations
        self.spacePinnedStructure = spacePinnedStructure
        self.profileAdmissions = profileAdmissions
    }

    func insert(_ pin: ShortcutPin, at targetIndex: Int) -> ShortcutPin? {
        withProfileReferenceLease(for: pin.profileReferenceIDs) {
            let aggregate = structuralMutations.prepareAggregate()
            guard aggregate != nil || structuralMutations.hasOpenAggregate else {
                return nil
            }
            guard let inserted = insertAdmitted(pin, at: targetIndex) else {
                if let aggregate { precondition(aggregate.rollback()) }
                return nil
            }
            settle(aggregate)
            return inserted
        }
    }

    func move(
        source: ShortcutPin,
        target: ShortcutPin,
        applying: ((ShortcutPin) -> Bool)?
    ) -> ShortcutPin? {
        withProfileReferenceLease(
            for: source.profileReferenceIDs.union(target.profileReferenceIDs)
        ) {
            guard pins.shortcutPin(by: source.id) === source else { return nil }
            let aggregate = structuralMutations.prepareAggregate()
            guard aggregate != nil || structuralMutations.hasOpenAggregate else {
                return nil
            }
            removeFromContainers(source)
            guard let inserted = insertAdmitted(target, at: target.index),
                  applying?(inserted) != false else {
                if let aggregate {
                    precondition(aggregate.rollback())
                } else {
                    removeFromContainers(target)
                    restoreToSource(source)
                }
                return nil
            }
            settle(aggregate)
            return inserted
        }
    }

    func removeFromContainers(_ pin: ShortcutPin) {
        switch pin.role {
        case .essential:
            guard let profileID = pin.profileId else { return }
            let remaining = pins.essentialPins(for: profileID).filter {
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

    private func insertAdmitted(
        _ pin: ShortcutPin,
        at targetIndex: Int
    ) -> ShortcutPin? {
        switch pin.role {
        case .essential:
            guard let profileID = pin.profileId else { return nil }
            var destination = pins.essentialPins(for: profileID)
            destination.removeAll { $0.id == pin.id }
            guard destination.count
                    < EssentialsShortcutPlacementOwner.CapacityPolicy.maxItems
            else { return nil }
            let safeIndex = max(0, min(targetIndex, destination.count))
            destination.insert(pin, at: safeIndex)
            let replacement = ShortcutPin.reindexed(destination)
            structuralMutations.setPinnedTabs(replacement, for: profileID)
            return replacement[safeIndex]
        case .spacePinned:
            guard let spaceID = pin.spaceId else { return nil }
            if pin.folderId == nil {
                return spacePinnedStructure.insertTopLevelSpacePinnedShortcut(
                    pin,
                    in: spaceID,
                    at: targetIndex
                )
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

    private func restoreToSource(_ pin: ShortcutPin) {
        switch pin.role {
        case .essential:
            guard let profileID = pin.profileId else { return }
            var destination = pins.essentialPins(for: profileID)
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

    private func settle(
        _ aggregate: TabStructuralCollectionMutationOwner.PreparedAggregate?
    ) {
        guard let aggregate else { return }
        precondition(aggregate.stage())
        precondition(aggregate.publish())
    }

    private func withProfileReferenceLease<T>(
        for profileIDs: Set<UUID>,
        _ operation: () -> T?
    ) -> T? {
        let lease: ProfileReferenceMutationLease
        do {
            lease = try profileAdmissions.beginReferenceMutation(to: profileIDs)
        } catch {
            return nil
        }
        defer { precondition(profileAdmissions.endReferenceMutation(lease)) }
        return operation()
    }
}

extension ShortcutPin {
    var profileReferenceIDs: Set<UUID> {
        Set([profileId, executionProfileId].compactMap { $0 })
    }
}
