import Foundation
import SumiDomain

@MainActor
final class ShortcutPinCatalogMutationTransaction {
    private let containers: ShortcutPinContainerPlacement
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction
    private let profileAdmissions: ProfileReferenceAdmissionLedger

    init(
        containers: ShortcutPinContainerPlacement,
        structuralMutations: TabStructuralCollectionMutationOwner,
        spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction,
        profileAdmissions: ProfileReferenceAdmissionLedger
    ) {
        self.containers = containers
        self.structuralMutations = structuralMutations
        self.spacePinnedVisualOrder = spacePinnedVisualOrder
        self.profileAdmissions = profileAdmissions
    }

    func insert(
        _ pin: ShortcutPin,
        at targetIndex: Int,
        sidebarVisualMembership: ShortcutPinSidebarVisualMembership
    ) -> ShortcutPin? {
        withProfileReferenceLease(for: pin.profileReferenceIDs) {
            let aggregate = structuralMutations.prepareAggregate()
            guard aggregate != nil || structuralMutations.hasOpenAggregate else {
                return nil
            }
            guard let inserted = containers.insert(pin, at: targetIndex),
                  finalizePlacement(
                      of: inserted,
                      at: targetIndex,
                      sidebarVisualMembership: sidebarVisualMembership
                  ) else {
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
        sidebarVisualMembership: ShortcutPinSidebarVisualMembership,
        applying: ((ShortcutPin) -> Bool)?
    ) -> ShortcutPin? {
        withProfileReferenceLease(
            for: source.profileReferenceIDs.union(target.profileReferenceIDs)
        ) {
            guard containers.isCanonical(source) else { return nil }
            let aggregate = structuralMutations.prepareAggregate()
            guard aggregate != nil || structuralMutations.hasOpenAggregate else {
                return nil
            }
            containers.remove(source)
            guard let inserted = containers.insert(target, at: target.index),
                  finalizePlacement(
                      of: inserted,
                      at: target.index,
                      sidebarVisualMembership: sidebarVisualMembership,
                      applying: { applying?(inserted) != false }
                  ) else {
                if let aggregate {
                    precondition(aggregate.rollback())
                } else {
                    containers.remove(target)
                    containers.restore(source)
                }
                return nil
            }
            settle(aggregate)
            return inserted
        }
    }

    func removeFromContainers(_ pin: ShortcutPin) {
        containers.remove(pin)
    }

    private func finalizePlacement(
        of pin: ShortcutPin,
        at targetIndex: Int,
        sidebarVisualMembership: ShortcutPinSidebarVisualMembership,
        applying sideEffect: @escaping @MainActor () -> Bool = { true }
    ) -> Bool {
        guard sidebarVisualMembership == .standalone else {
            return sideEffect()
        }
        guard pin.role == .spacePinned,
              let spaceID = pin.spaceId else {
            return sideEffect()
        }
        return spacePinnedVisualOrder.placeExisting(
            .shortcut(pin.id),
            in: spaceID,
            folderID: pin.folderId,
            at: targetIndex,
            applying: sideEffect
        )
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
