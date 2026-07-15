import Foundation
import SumiWebRuntime
import WebKit

/// Strict heterogeneous profile replacement used by shortcut binding. It does
/// not enqueue per-Tab retries because they cannot preserve batch atomicity.
@MainActor
final class PreparedProfileAssignmentBatchTransitionService {
    struct Runtime {
        let webViewSessions: WebViewSessionRepository
        let admissionIsBlocked: (UUID) -> Bool
        let isProtected: (WKWebView) -> Bool
        let provisioning: ProfileReplacementProvisioning
        let pipeline: WebViewReplacementPipeline
        let activation: ReplacementNavigationActivation
    }

    private let runtime: Runtime

    init(runtime: Runtime) {
        self.runtime = runtime
    }

    func transition(
        assignments: [PreparedTabProfileAssignment],
        bindingModel: any ShortcutTabBindingAggregateTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> PreparedProfileAssignmentBatchTransitionOutcome {
        let tabs = assignments.map(\.tab)
        guard Set(tabs.map(\.id)).count == tabs.count,
              assignments.allSatisfy({ $0.isCurrent() }) else {
            return .rejectedUnstaged(.stale)
        }
        let model = PreparedProfileAssignmentBatchModelTransaction(
            assignments: assignments,
            binding: bindingModel
        )
        guard model.validateForStaging() else {
            return .rejectedUnstaged(.stale)
        }
        let physicalAssignments = assignments.filter(
            \.requiresPhysicalReplacement
        )
        let profileIDs = assignments.reduce(into: Set<UUID>()) {
            result, item in
            result.insert(item.targetProfile.id)
            result.insert(item.sourceResolvedProfileID)
        }
        guard profileIDs.allSatisfy({ !runtime.admissionIsBlocked($0) }) else {
            return .rejectedUnstaged(.failed)
        }

        let snapshots = Dictionary(uniqueKeysWithValues: tabs.map {
            ($0.id, runtime.webViewSessions.snapshot(for: $0.id))
        })
        guard physicalAssignments.allSatisfy({ assignment in
            snapshots[assignment.tab.id].map(
                assignment.physicalEvidenceIsCurrent(in:)
            ) == true
        }) else {
            return .rejectedUnstaged(.stale)
        }
        guard physicalAssignments.isEmpty == false else {
            return executeModelOnly(model, settlement: settlement)
        }
        let physicalTabIDs = Set(physicalAssignments.map { $0.tab.id })
        let live = snapshots.filter {
            physicalTabIDs.contains($0.key)
                && $0.value.allKnownWebViews.isEmpty == false
        }
        guard !live.isEmpty else {
            return executeModelOnly(model, settlement: settlement)
        }
        guard !live.values.flatMap(\.allKnownWebViews)
            .contains(where: runtime.isProtected) else {
            return .rejectedUnstaged(.failed)
        }
        guard let prepared = runtime.provisioning.prepare(
            assignments: physicalAssignments,
            liveSnapshots: live,
            reason: "shortcut-binding"
        ) else {
            return .rejectedUnstaged(.failed)
        }
        return begin(
            prepared,
            profileIDs: profileIDs,
            model: model,
            settlement: settlement
        )
    }

    private func begin(
        _ prepared: [PreparedWebViewReplacement],
        profileIDs: Set<UUID>,
        model: PreparedProfileAssignmentBatchModelTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> PreparedProfileAssignmentBatchTransitionOutcome {
        let start = runtime.pipeline.begin(
            prepared,
            profileIDs: profileIDs,
            model: .transaction(model),
            completion: { outcome in
                self.complete(
                    outcome,
                    prepared: prepared,
                    settlement: settlement
                )
            }
        )
        switch start {
        case .started(let receipt):
            runtime.activation.activate(
                prepared,
                receipt: receipt,
                reason: "shortcut-binding"
            )
            return .pipelineOwned
        case .committed:
            runtime.activation.activateWithoutNavigation(
                prepared,
                reason: "shortcut-binding"
            )
            return .committed
        case .conflict, .stale, .modelValidationFailed:
            runtime.provisioning.discard(prepared)
            return .rejectedUnstaged(.stale)
        case .modelCommitFailed:
            settlement(.rejected(.stale))
            return .rejectedSettled
        case .invalid:
            runtime.provisioning.discard(prepared)
            return .rejectedUnstaged(.failed)
        case .rolledBack:
            return .rejectedSettled
        case .settlementConflict(let delivery):
            if delivery == .callerOwned { settlement(.conflicted) }
            return .conflicted
        case .leaseLost(let delivery):
            if delivery == .callerOwned { settlement(.leaseLost) }
            return .rejectedSettled
        }
    }

    private func executeModelOnly(
        _ model: PreparedProfileAssignmentBatchModelTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> PreparedProfileAssignmentBatchTransitionOutcome {
        let outcome = ProfileTransitionModelOnlySettlement.execute(
            .transaction(model)
        )
        settlement(outcome.settlement)
        return outcome.batchExecution
    }

    private func complete(
        _ outcome: WebViewReplacementTransactionOutcome,
        prepared: [PreparedWebViewReplacement],
        settlement: @escaping ProfileTransitionService.Settlement
    ) {
        switch outcome {
        case .committed:
            runtime.activation.finishCommitted(
                prepared,
                reason: "shortcut-binding"
            )
            settlement(.committed)
        case .rolledBack(let reason): settlement(.rolledBack(reason))
        case .conflicted: settlement(.conflicted)
        case .leaseLost: settlement(.leaseLost)
        case .abandonedForTerminalShutdown: settlement(.terminalShutdown)
        }
    }
}
