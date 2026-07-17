import Foundation
import SumiDomain

/// Applies an already-computed shortcut reference plan and owns its exact
/// persistence/publication effects.
@MainActor
final class ShortcutProfileReferenceMutationApplicator {
    private let structure: ShortcutProfileReferenceStructureMutation
    private let topology: ShortcutProfileReferenceTopologyMutation
    private let runtimeConnection: TabRuntimePortConnection
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger

    init(
        structure: ShortcutProfileReferenceStructureMutation,
        topology: ShortcutProfileReferenceTopologyMutation,
        runtimeConnection: TabRuntimePortConnection,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger
    ) {
        self.structure = structure
        self.topology = topology
        self.runtimeConnection = runtimeConnection
        self.profileReferenceAdmission = profileReferenceAdmission
    }

    func apply(
        _ plan: ShortcutProfileReferenceMutationPlan,
        using runtimeLease: TabRuntimePortLease,
        referenceMutationLease: ProfileReferenceMutationLease?
    ) -> Bool {
        guard accepts(
            plan,
            runtimeLease: runtimeLease,
            referenceMutationLease: referenceMutationLease
        ) else { return false }
        guard !plan.isEmpty else { return true }
        guard let aggregate = structure.prepareAggregate() else {
            return false
        }

        let splitReceipt: SplitGroupReplacementReceipt?
        if let splitReplacement = plan.splitReplacement {
            guard let receipt = topology.prepare(splitReplacement) else {
                precondition(aggregate.rollback())
                return false
            }
            splitReceipt = receipt
        } else {
            splitReceipt = nil
        }

        guard structure.apply(plan) else {
            splitReceipt?.rollback()
            precondition(aggregate.rollback())
            return false
        }

        guard accepts(
            plan,
            runtimeLease: runtimeLease,
            referenceMutationLease: referenceMutationLease
        ), splitReceipt?.commitModel() ?? true,
            aggregate.stage(),
            accepts(
                plan,
                runtimeLease: runtimeLease,
                referenceMutationLease: referenceMutationLease
            ) else {
            rollback(splitReceipt, aggregate: aggregate)
            return false
        }
        guard aggregate.publish() else {
            rollback(splitReceipt, aggregate: aggregate)
            return false
        }
        if let splitReceipt {
            guard let replacement = plan.splitReplacement?.replacement,
                  topology.publish(
                      splitReceipt,
                      expected: replacement
                  ) else {
                return false
            }
        }
        structure.schedulePersistence()
        return accepts(
            plan,
            runtimeLease: runtimeLease,
            referenceMutationLease: referenceMutationLease
        )
    }

    private func accepts(
        _ plan: ShortcutProfileReferenceMutationPlan,
        runtimeLease: TabRuntimePortLease,
        referenceMutationLease: ProfileReferenceMutationLease?
    ) -> Bool {
        guard runtimeConnection.acceptsExactAttachment(runtimeLease) else {
            return false
        }
        guard plan.requiresFallbackAdmission else { return true }
        guard let referenceMutationLease else { return false }
        return profileReferenceAdmission.validate(
            referenceMutationLease,
            covers: [plan.fallbackProfileID]
        )
    }

    private func rollback(
        _ splitReceipt: SplitGroupReplacementReceipt?,
        aggregate: TabStructuralCollectionMutationOwner.PreparedAggregate
    ) {
        if let splitReceipt, splitReceipt.committedModelIsExact() {
            precondition(splitReceipt.rollbackModel())
        } else {
            splitReceipt?.rollback()
        }
        _ = aggregate.rollback()
    }
}
