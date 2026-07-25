import Foundation

/// Acquires the exclusive right to move the extension runtime onto one profile.
/// A caller may supply a lease it already owns; otherwise this role opens a
/// mutation lease — falling back to a retirement migration — and hands back the
/// admission receipt plus who is responsible for ending it.
@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileTransitionLease {
    struct Grant {
        let profileAdmission: ProfileReferenceAdmissionReceipt
        let mutationLease: ProfileReferenceMutationLease
        let ownsMutationLease: Bool
    }

    private let profileRuntime: ExtensionProfileRuntime

    init(profileRuntime: ExtensionProfileRuntime) {
        self.profileRuntime = profileRuntime
    }

    func acquire(
        profileID: UUID,
        suppliedMutationLease: ProfileReferenceMutationLease?
    ) -> Grant? {
        guard let profileAdmission = profileRuntime.admitProfileReference(
            to: profileID
        ), let mutationLease = suppliedMutationLease
            ?? profileRuntime.beginProfileReferenceMutation(to: profileID)
            ?? profileRuntime.beginProfileRetirementMigration(to: profileID),
           profileRuntime.validateProfileReferenceMutation(
            mutationLease,
            profileID: profileID
           ) else { return nil }
        return Grant(
            profileAdmission: profileAdmission,
            mutationLease: mutationLease,
            ownsMutationLease: suppliedMutationLease == nil
        )
    }

    func release(_ grant: Grant) {
        guard grant.ownsMutationLease else { return }
        precondition(
            profileRuntime.endProfileReferenceMutation(grant.mutationLease)
        )
    }
}
