import Foundation
import SumiDomain

/// Owns the exact live shortcut and split-topology boundary for one profile
/// retirement. WebView transitions and selection effects remain outside it.
@MainActor
final class ShortcutProfileReferenceRetirementService {
    private let pins: ShortcutPinCollectionStateOwner
    private let splitGroups: SplitGroupStore
    private let pendingPins: PendingShortcutPinAdopter
    private let mutations: ShortcutProfileReferenceMutationApplicator
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger

    init(
        pins: ShortcutPinCollectionStateOwner,
        splitGroups: SplitGroupStore,
        pendingPins: PendingShortcutPinAdopter,
        mutations: ShortcutProfileReferenceMutationApplicator,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger
    ) {
        self.pins = pins
        self.splitGroups = splitGroups
        self.pendingPins = pendingPins
        self.mutations = mutations
        self.profileReferenceAdmission = profileReferenceAdmission
    }

    func migrate(
        deletedProfileID: UUID,
        fallbackProfileID: UUID,
        using runtimeLease: TabRuntimePortLease
    ) -> Bool {
        guard let plan = ShortcutProfileReferenceMutationPlanner().plan(
            deleting: deletedProfileID,
            fallbackProfileID: fallbackProfileID,
            state: pins,
            splitGroups: splitGroups.groups
        ) else { return false }
        let referenceMutationLease: ProfileReferenceMutationLease?
        if plan.requiresFallbackAdmission {
            do {
                referenceMutationLease = try profileReferenceAdmission
                    .beginRetirementReferenceMigration(
                        to: [fallbackProfileID]
                    )
            } catch {
                return false
            }
        } else {
            referenceMutationLease = nil
        }
        defer {
            if let referenceMutationLease {
                precondition(
                    profileReferenceAdmission.endReferenceMutation(
                        referenceMutationLease
                    )
                )
            }
        }
        guard mutations.apply(
            plan,
            using: runtimeLease,
            referenceMutationLease: referenceMutationLease
        ) else { return false }
        pendingPins.cancelDeferredAdoption(referencing: deletedProfileID)
        return containsReference(to: deletedProfileID) == false
    }

    func containsReference(to profileID: UUID) -> Bool {
        pendingPins.containsReference(to: profileID)
            || ProfileReferenceInventory(
                shortcutPins: pins,
                splitGroups: splitGroups.groups
            ).contains(profileID)
    }
}
