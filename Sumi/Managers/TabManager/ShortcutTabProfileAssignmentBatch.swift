import Foundation
import SumiWebRuntime

@MainActor
struct ShortcutTabProfileAssignmentAdmission {
    let assignment: PreparedTabProfileAssignment

    func isCurrent(using lease: TabRuntimePortLease) -> Bool {
        assignment.isCurrent() && lease.accepts(assignment)
    }
}

/// Executes one exact attachment's heterogeneous profile assignments with the
/// caller's unpublished binding model as a single repository transaction.
@MainActor
final class ShortcutTabProfileAssignmentBatch {
    private let connection: TabRuntimePortConnection
    private let lease: TabRuntimePortLease
    private let admissions: [ShortcutTabProfileAssignmentAdmission]

    init(
        connection: TabRuntimePortConnection,
        lease: TabRuntimePortLease,
        admissions: [ShortcutTabProfileAssignmentAdmission]
    ) {
        self.connection = connection
        self.lease = lease
        self.admissions = admissions
    }

    func isCurrent(
        for bindingModel: any ShortcutTabBindingAggregateTransaction
    ) -> Bool {
        let bindingTabIDs = bindingModel.exactBindingTabs.map(
            ObjectIdentifier.init
        )
        let admissionTabIDs = admissions.map {
            ObjectIdentifier($0.assignment.tab)
        }
        return Set(bindingTabIDs).count == bindingTabIDs.count
            && Set(admissionTabIDs).count == admissionTabIDs.count
            && Set(bindingTabIDs) == Set(admissionTabIDs)
            && lease.registry != nil
            && connection.acceptsExactAttachment(lease)
            && admissions.allSatisfy { $0.isCurrent(using: lease) }
    }

    func execute(
        bindingModel: any ShortcutTabBindingAggregateTransaction,
        settlement: @escaping ProfileTransitionService.Settlement = { _ in }
    ) -> PreparedProfileAssignmentBatchTransitionOutcome {
        guard isCurrent(for: bindingModel) else {
            return settleUnstagedRejection(
                .stale,
                bindingModel: bindingModel,
                settlement: settlement
            )
        }
        let assignments = admissions.map(\.assignment)
        let outcome = lease.executePreparedProfileAssignments(
            assignments,
            bindingModel: bindingModel,
            settlement: settlement
        ) ?? .rejectedUnstaged(.stale)
        if case .rejectedUnstaged(let reason) = outcome {
            return settleUnstagedRejection(
                reason,
                bindingModel: bindingModel,
                settlement: settlement
            )
        }
        return outcome
    }

    private func settleUnstagedRejection(
        _ reason: ProfileTransitionRejectionReason,
        bindingModel: any ShortcutTabBindingAggregateTransaction,
        settlement: ProfileTransitionService.Settlement
    ) -> PreparedProfileAssignmentBatchTransitionOutcome {
        guard bindingModel.cancelPrepared() else {
            settlement(.conflicted)
            return .conflicted
        }
        settlement(.rejected(reason))
        return .rejectedUnstaged(reason)
    }
}
