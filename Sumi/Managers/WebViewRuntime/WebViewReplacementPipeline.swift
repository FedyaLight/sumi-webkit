import Foundation
import SumiWebRuntime
import WebKit

@MainActor
struct PreparedWebViewReplacement {
    let tab: Tab
    let snapshot: WebViewSessionSnapshot
    let placement: WebViewReplacementPlacement
    let replacements: [WKWebView]
    let trackedReplacements: [WKWebView]
    let bindingReplacements: [WKWebView]
    let targetURL: URL
    let semanticRevision: UInt64
    let profileID: UUID?
    let requiresExtensionRuntimePreparation: Bool
    let configurationPolicyChangeSet:
        PreparedConfigurationPolicyChangeSet?

    init?(
        tab: Tab,
        snapshot: WebViewSessionSnapshot,
        placement: WebViewReplacementPlacement,
        replacements: [WKWebView],
        trackedReplacements: [WKWebView],
        bindingReplacements: [WKWebView],
        targetURL: URL,
        semanticRevision: UInt64,
        profileID: UUID?,
        requiresExtensionRuntimePreparation: Bool,
        configurationPolicyChangeSet:
            PreparedConfigurationPolicyChangeSet?
    ) {
        let replacementIDs = Set(
            replacements.map(ObjectIdentifier.init)
        )
        let placedWebViews = Self.webViews(in: placement)
        let normalReplacements = replacements.filter {
            $0.configuration.sumiIsNormalTabWebViewConfiguration
        }
        let auxiliaryReplacementsHaveNoPolicyEvidence = replacements
            .filter {
                $0.configuration.sumiIsNormalTabWebViewConfiguration == false
            }
            .allSatisfy {
                $0.sumiPreparedConfigurationPolicyChange == nil
            }
        let trackedReplacementIDs = Set(
            trackedReplacements.map(ObjectIdentifier.init)
        )
        let expectedTrackedReplacementIDs: Set<ObjectIdentifier>
        switch placement {
        case .windowSet:
            expectedTrackedReplacementIDs = replacementIDs
        case .detached:
            expectedTrackedReplacementIDs = []
        }
        guard replacements.isEmpty == false,
              replacementIDs.count == replacements.count,
              Set(placedWebViews.map(ObjectIdentifier.init))
                == replacementIDs,
              placedWebViews.count == replacements.count,
              trackedReplacementIDs.count == trackedReplacements.count,
              trackedReplacementIDs == expectedTrackedReplacementIDs,
              Self.isUniqueSubset(
                  bindingReplacements,
                  of: replacementIDs
              ),
              normalReplacements.isEmpty
                || normalReplacements.count == replacements.count,
              normalReplacements.isEmpty
                ? configurationPolicyChangeSet == nil
                    && auxiliaryReplacementsHaveNoPolicyEvidence
                : configurationPolicyChangeSet?.canCommit(
                    for: replacements,
                    as: .canonicalGeneration
                ) == true,
              configurationPolicyChangeSet?.expectedSessionGeneration
                == snapshot.generation
                || configurationPolicyChangeSet == nil,
              configurationPolicyChangeSet?.belongs(
                  to: tab.configurationPolicyLedger
              ) != false,
              configurationPolicyChangeSet?.profileID == profileID
                || configurationPolicyChangeSet == nil else {
            return nil
        }
        self.tab = tab
        self.snapshot = snapshot
        self.placement = placement
        self.replacements = replacements
        self.trackedReplacements = trackedReplacements
        self.bindingReplacements = bindingReplacements
        self.targetURL = targetURL
        self.semanticRevision = semanticRevision
        self.profileID = profileID
        self.requiresExtensionRuntimePreparation =
            requiresExtensionRuntimePreparation
        self.configurationPolicyChangeSet = configurationPolicyChangeSet
    }

    private static func webViews(
        in placement: WebViewReplacementPlacement
    ) -> [WKWebView] {
        switch placement {
        case .windowSet(let webViewsByWindowID, _):
            return Array(webViewsByWindowID.values)
        case .detached(let webView, _):
            return [webView]
        }
    }

    private static func isUniqueSubset(
        _ webViews: [WKWebView],
        of replacementIDs: Set<ObjectIdentifier>
    ) -> Bool {
        let identities = webViews.map(ObjectIdentifier.init)
        return Set(identities).count == identities.count
            && identities.allSatisfy(replacementIDs.contains)
    }
}

enum WebViewReplacementPipelineStart {
    case started(WebViewReplacementSettlementReceipt)
    case committed
    case stale
    case conflict
    case invalid
    /// Admission failed before repository apply; the caller owns cleanup.
    case modelValidationFailed
    /// Repository apply was compensated and the pipeline consumed cleanup of
    /// the discarded replacement generation.
    case modelCommitFailed
    case rolledBack(WebViewReplacementRollbackReason)
    case settlementConflict
    case leaseLost
}

/// App-level transaction boundary shared by every whole-session replacement.
/// It atomically admits concrete placements and registers their settlement
/// lease before returning a receipt that permits asynchronous activation.
@MainActor
final class WebViewReplacementPipeline {
    private struct ConfigurationPolicyEvidenceInvalidated: Error {}
    private struct ModelRollbackEvidenceInvalidated: Error {}

    struct Runtime {
        let webViewSessions: WebViewSessionRepository
        let quiesce: (WKWebView) -> Void
        let retiredGenerationDestroyer: WebViewRetiredGenerationDestroyer
        let restore: (UUID, WebViewSessionSnapshot) -> Void
    }

    private let runtime: Runtime
    private var configurationPolicyChangesByLease: [
        WebViewReplacementBatchLease:
            [PreparedConfigurationPolicyChangeSet]
    ] = [:]
    private lazy var settlementService = WebViewReplacementSettlementService(
        runtime: WebViewReplacementSettlementRuntime(
            validateCommitLease: { [weak self] lease in
                self?.configurationPolicyChangesCanCommit(for: lease) == true
            },
            commitLease: { [weak self, runtime] lease in
                let result = runtime.webViewSessions
                    .commitReplacementBatch(lease)
                if case .committed = result {
                    self?.commitConfigurationPolicyChanges(for: lease)
                }
                return result
            },
            rollbackLease: { [weak self, runtime] lease, modelRollback in
                let result = runtime.webViewSessions.rollbackReplacementBatch(
                    lease,
                    modelRollback: modelRollback
                )
                if case .rolledBack = result {
                    self?.cancelConfigurationPolicyChanges(for: lease)
                }
                return result
            },
            quiesceRetired: { [runtime] snapshots in
                snapshots.values
                    .flatMap(\.allKnownWebViews)
                    .forEach(runtime.quiesce)
            },
            retireCommitted: { [runtime] snapshots in
                runtime.retiredGenerationDestroyer.destroy(snapshots)
            },
            restoreAfterRollback: { [runtime] discarded, retired, _ in
                runtime.retiredGenerationDestroyer.destroy(discarded)
                for (tabID, snapshot) in retired {
                    runtime.restore(tabID, snapshot)
                }
            },
            observeSettlement: { _ in
                // The app pipeline exposes typed completion receipts instead
                // of duplicating package settlement events as telemetry.
            }
        )
    )

    init(runtime: Runtime) {
        self.runtime = runtime
    }

    func begin(
        _ replacements: [PreparedWebViewReplacement],
        profileIDs: Set<UUID>,
        model: WebViewReplacementModelParticipant,
        completion: @escaping @MainActor (
            WebViewReplacementTransactionOutcome
        ) -> Void
    ) -> WebViewReplacementPipelineStart {
        precondition(replacements.isEmpty == false)

        guard Self.configurationPolicyChangesCanCommit(in: replacements) else {
            cancelConfigurationPolicyChanges(in: replacements)
            return .invalid
        }

        var policyEvidenceWasInvalidated = false
        var modelWasStaged = false
        let validateTransaction = {
            let modelIsValid = model.validateForStaging()
            let policyIsValid = Self.configurationPolicyChangesCanCommit(
                in: replacements
            )
            policyEvidenceWasInvalidated = policyIsValid == false
            return modelIsValid && policyIsValid
        }
        let commitModel = {
            guard Self.configurationPolicyChangesCanCommit(
                in: replacements
            ) else {
                policyEvidenceWasInvalidated = true
                throw ConfigurationPolicyEvidenceInvalidated()
            }
            do {
                try model.stage()
                modelWasStaged = true
            } catch {
                policyEvidenceWasInvalidated =
                    Self.configurationPolicyChangesCanCommit(
                        in: replacements
                    ) == false
                throw error
            }
            guard Self.configurationPolicyChangesCanCommit(
                in: replacements
            ) else {
                policyEvidenceWasInvalidated = true
                throw ConfigurationPolicyEvidenceInvalidated()
            }
        }
        let rollbackModelAfterFailedCommit = {
            guard modelWasStaged else { return }
            guard model.stagedModelIsExact() else {
                throw ModelRollbackEvidenceInvalidated()
            }
            try model.rollback()
        }
        let retired = Dictionary(
            uniqueKeysWithValues: replacements.map {
                ($0.tab.id, $0.snapshot)
            }
        )

        let begin = runtime.webViewSessions.beginReplacementBatch(
            replacements.map {
                WebViewReplacementBatchEntry(
                    tabID: $0.tab.id,
                    expectedGeneration: $0.snapshot.generation,
                    placement: $0.placement
                )
            },
            validateModel: validateTransaction,
            modelCommit: commitModel,
            modelRollback: rollbackModelAfterFailedCommit
        )
        guard case .began(let lease) = begin else {
            cancelConfigurationPolicyChanges(in: replacements)
            switch begin {
            case .stale:
                return .stale
            case .conflict:
                return .conflict
            case .invalid:
                return .invalid
            case .modelValidationFailed:
                return policyEvidenceWasInvalidated
                    ? .invalid
                    : .modelValidationFailed
            case .modelCommitFailed(let discarded):
                runtime.retiredGenerationDestroyer.destroy(discarded)
                if modelWasStaged {
                    model.publishRollback()
                }
                return .modelCommitFailed
            case .modelRollbackFailed(let lease):
                settlementService.retainConflictedAdmission(
                    lease: lease,
                    tabIDs: Set(retired.keys),
                    profileIDs: profileIDs,
                    retired: retired,
                    model: model
                )
                return .settlementConflict
            case .noLongerActive:
                if modelWasStaged {
                    model.settleTerminalDrain()
                }
                return .leaseLost
            case .began:
                preconditionFailure("Handled replacement batch admission")
            }
        }

        let requiredBindings = replacements.flatMap { replacement in
            replacement.bindingReplacements.map {
                WebViewReplacementBindingRequirement(
                    webView: $0,
                    semanticRevision: replacement.semanticRevision
                )
            }
        }
        configurationPolicyChangesByLease[lease] = replacements.compactMap(
            \.configurationPolicyChangeSet
        )
        switch settlementService.start(
            lease: lease,
            tabIDs: Set(retired.keys),
            profileIDs: profileIDs,
            retired: retired,
            requiredBindings: requiredBindings,
            model: model,
            completion: { outcome in
                if outcome != .committed {
                    self.cancelConfigurationPolicyChanges(for: lease)
                }
                self.configurationPolicyChangesByLease
                    .removeValue(forKey: lease)
                switch outcome {
                case .committed:
                    model.publishCommit()
                case .rolledBack:
                    model.publishRollback()
                case .conflicted, .leaseLost, .abandonedForTerminalShutdown:
                    break
                }
                completion(outcome)
            }
        ) {
        case .started(let receipt):
            return .started(receipt)
        case .committed:
            return .committed
        case .rolledBack(_, let reason):
            return .rolledBack(reason)
        case .conflicted:
            return .settlementConflict
        case .leaseLost:
            return .leaseLost
        }
    }

    @discardableResult
    func markBound(
        _ token: WebViewReplacementBindingToken,
        binding: WebViewReplacementNavigationBinding
    ) -> WebViewReplacementBindingAcceptance {
        settlementService.markBound(token, binding: binding)
    }

    func fail(
        _ token: WebViewReplacementBindingToken,
        reason: WebViewReplacementBindingFailureReason
    ) {
        _ = settlementService.fail(token, reason: reason)
    }

    @discardableResult
    func abort(
        profileIDs: Set<UUID>,
        reason: WebViewReplacementAbortReason
    ) -> Int {
        settlementService.abortForProfiles(profileIDs, reason: reason)
    }

    @discardableResult
    func abort(
        tabIDs: Set<UUID>,
        reason: WebViewReplacementAbortReason
    ) -> Int {
        settlementService.abortForTabs(tabIDs, reason: reason)
    }

    /// Repository terminal drain owns both the retired and replacement
    /// generations. Complete every outstanding receipt and cancel settlement
    /// timeouts without attempting a second rollback against the drained
    /// repository.
    func resetForTerminalShutdown() {
        settlementService.resetForTerminalShutdown()
    }

    private static func configurationPolicyChangesCanCommit(
        in replacements: [PreparedWebViewReplacement]
    ) -> Bool {
        replacements.allSatisfy { replacement in
            replacement.configurationPolicyChangeSet?.canCommit(
                for: replacement.replacements,
                as: .canonicalGeneration
            ) != false
        }
    }

    private func configurationPolicyChangesCanCommit(
        for lease: WebViewReplacementBatchLease
    ) -> Bool {
        guard let changeSets = configurationPolicyChangesByLease[lease] else {
            return false
        }
        return changeSets.allSatisfy {
            $0.canCommit(as: .canonicalGeneration)
        }
    }

    private func commitConfigurationPolicyChanges(
        for lease: WebViewReplacementBatchLease
    ) {
        for changeSet in configurationPolicyChangesByLease[lease] ?? [] {
            precondition(
                changeSet.commit(as: .canonicalGeneration),
                "Committed WebView generation carried a stale policy receipt"
            )
        }
    }

    private func cancelConfigurationPolicyChanges(
        for lease: WebViewReplacementBatchLease
    ) {
        configurationPolicyChangesByLease[lease]?.forEach { $0.cancel() }
    }

    private func cancelConfigurationPolicyChanges(
        in replacements: [PreparedWebViewReplacement]
    ) {
        replacements.forEach { replacement in
            replacement.configurationPolicyChangeSet?.cancel()
        }
    }
}
