import Foundation
import SumiDomain
import WebKit
import SumiWebRuntime

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
    let previousProtectionState: SumiProtectionAttachmentState?
    let previousSafariContentBlockerState:
        SumiSafariContentBlockerAttachmentState?
}

enum WebViewReplacementPipelineStart {
    case started(WebViewReplacementSettlementReceipt)
    case committed
    case stale
    case conflict
    case invalid
    case modelCommitFailed
    case settlementConflict
    case leaseLost
}

/// App-level transaction boundary shared by every whole-session replacement.
/// It atomically admits concrete placements and registers their settlement
/// lease before returning a receipt that permits asynchronous activation.
@MainActor
final class WebViewReplacementPipeline {
    struct Runtime {
        let webViewSessions: WebViewSessionRepository
        let quiesce: (WKWebView) -> Void
        let destroy: (UUID, WKWebView) -> Void
        let restore: (UUID, WebViewSessionSnapshot) -> Void
        let uninstallObservationsIfUntracked: (WKWebView) -> Void
    }

    private let runtime: Runtime
    private lazy var settlementService = WebViewReplacementSettlementService(
        runtime: WebViewReplacementSettlementRuntime(
            commitLease: { [runtime] lease in
                runtime.webViewSessions.commitReplacementBatch(lease)
            },
            rollbackLease: { [runtime] lease, modelRollback in
                runtime.webViewSessions.rollbackReplacementBatch(
                    lease,
                    modelRollback: modelRollback
                )
            },
            quiesceRetired: { [runtime] snapshots in
                snapshots.values
                    .flatMap(\.allKnownWebViews)
                    .forEach(runtime.quiesce)
            },
            retireCommitted: { [runtime] snapshots in
                Self.destroy(
                    snapshots,
                    runtime: runtime
                )
            },
            restoreAfterRollback: { [runtime] discarded, retired, _ in
                Self.destroy(
                    discarded,
                    runtime: runtime
                )
                for (tabID, snapshot) in retired {
                    runtime.restore(tabID, snapshot)
                }
            }
        )
    )

    init(runtime: Runtime) {
        self.runtime = runtime
    }

    func begin(
        _ replacements: [PreparedWebViewReplacement],
        profileIDs: Set<UUID>,
        validateModel: @escaping @MainActor () -> Bool,
        modelCommit: @escaping @MainActor () throws -> Void,
        modelRollback: @escaping WebViewReplacementModelRollback,
        completion: @escaping @MainActor (
            WebViewReplacementTransactionOutcome
        ) -> Void
    ) -> WebViewReplacementPipelineStart {
        precondition(replacements.isEmpty == false)

        let begin = runtime.webViewSessions.beginReplacementBatch(
            replacements.map {
                WebViewReplacementBatchEntry(
                    tabID: $0.tab.id,
                    expectedGeneration: $0.snapshot.generation,
                    placement: $0.placement
                )
            },
            validateModel: validateModel,
            modelCommit: modelCommit
        )
        guard case .began(let lease) = begin else {
            switch begin {
            case .stale:
                return .stale
            case .conflict:
                return .conflict
            case .invalid:
                return .invalid
            case .modelCommitFailed:
                return .modelCommitFailed
            case .began:
                preconditionFailure("Handled replacement batch admission")
            }
        }

        let retired = Dictionary(
            uniqueKeysWithValues: replacements.map {
                ($0.tab.id, $0.snapshot)
            }
        )
        let requiredBindings = replacements.flatMap { replacement in
            replacement.bindingReplacements.map {
                WebViewReplacementBindingRequirement(
                    webView: $0,
                    semanticRevision: replacement.semanticRevision
                )
            }
        }
        switch settlementService.start(
            lease: lease,
            tabIDs: Set(retired.keys),
            profileIDs: profileIDs,
            retired: retired,
            requiredBindings: requiredBindings,
            modelRollback: modelRollback,
            completion: completion
        ) {
        case .started(let receipt):
            return .started(receipt)
        case .committed:
            return .committed
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

    private static func destroy(
        _ snapshots: [UUID: WebViewSessionSnapshot],
        runtime: Runtime
    ) {
        for (tabID, snapshot) in snapshots {
            for webView in snapshot.allKnownWebViews {
                runtime.uninstallObservationsIfUntracked(webView)
                runtime.destroy(tabID, webView)
            }
        }
    }
}
