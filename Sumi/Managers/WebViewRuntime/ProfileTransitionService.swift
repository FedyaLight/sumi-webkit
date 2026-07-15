import Foundation
import SumiWebRuntime
import WebKit

enum ProfileTransitionSettlement: Equatable {
    case committed
    case rejected(ProfileTransitionRejectionReason)
    case rolledBack(WebViewReplacementRollbackReason)
    case conflicted
    case leaseLost
    case terminalShutdown
}

/// Translates effective-profile intent into one generic replacement request.
/// Provisioning, repository settlement, and navigation activation are separate
/// collaborators so this service owns only profile-transition policy.
@MainActor
final class ProfileTransitionService {
    struct Runtime {
        let webViewSessions: WebViewSessionRepository
        let admissionIsBlocked: (UUID) -> Bool
        let deferAdmission: (
            UUID,
            WebsiteDataMutationGate.DeferredAdmissionKey,
            @escaping @MainActor () -> Void
        ) -> Bool
        let isProtected: (WKWebView) -> Bool
        let deferProtectedCommand: (
            DeferredWebViewCommand,
            WKWebView,
            String
        ) -> DeferredProtectedCommandSchedulingOutcome
        let provisioning: ProfileReplacementProvisioning
        let pipeline: WebViewReplacementPipeline
        let activation: ReplacementNavigationActivation
    }

    typealias Settlement = @MainActor (ProfileTransitionSettlement) -> Void

    private enum RequestKind {
        case tab(UUID, DeferredWebViewProfileAssignmentIntent)
        case space(DeferredWebViewSpaceProfileAssignmentIntent)

        var admissionKey: WebsiteDataMutationGate.DeferredAdmissionKey {
            switch self {
            case .tab(let tabID, _): .profileAssignment(tabID: tabID)
            case .space(let intent):
                .spaceProfileAssignment(spaceID: intent.spaceID)
            }
        }

        var reason: String {
            switch self {
            case .tab: "profile-assignment"
            case .space: "space-profile-assignment"
            }
        }

        func deferredCommand(
            _ snapshot: WebViewSessionSnapshot
        ) -> DeferredWebViewCommand {
            switch self {
            case .tab(let tabID, let intent):
                .assignProfile(
                    tabID: tabID,
                    preferredPrimaryWindowID: snapshot.primaryWindowID,
                    intent: intent
                )
            case .space(let intent):
                .assignSpaceProfile(intent: intent)
            }
        }
    }

    private struct Request {
        let targetProfile: Profile
        let tabs: [Tab]
        let intentsByTabID: [UUID: DeferredWebViewProfileAssignmentIntent]
        let model: WebViewReplacementModelParticipant
        let kind: RequestKind

        var admissionKey: WebsiteDataMutationGate.DeferredAdmissionKey {
            kind.admissionKey
        }

        var reason: String { kind.reason }
    }

    private let runtime: Runtime

    init(runtime: Runtime) {
        self.runtime = runtime
    }

    func transition(
        tab: Tab,
        to targetProfile: Profile,
        intent: DeferredWebViewProfileAssignmentIntent,
        settlement: @escaping Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        execute(
            Request(
                targetProfile: targetProfile,
                tabs: [tab],
                intentsByTabID: [tab.id: intent],
                model: .transaction(ProfileTransitionModelParticipant(
                    model: TabProfileAssignmentModelTransaction(
                        tab: tab,
                        targetProfileID: targetProfile.id,
                        intent: intent
                    ),
                    tabs: [tab]
                )),
                kind: .tab(tab.id, intent)
            ),
            settlement: settlement
        )
    }

    func transition(
        spaceID: UUID,
        to targetProfile: Profile,
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        tabsByID: [UUID: Tab],
        model: any WebViewReplacementModelTransaction,
        settlement: @escaping Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        let tabs = intent.tabIntents.compactMap { tabsByID[$0.tabID] }
        let intentTabIDs = intent.tabIntents.map(\.tabID)
        guard tabs.count == intent.tabIntents.count,
              Set(intentTabIDs).count == intentTabIDs.count,
              intent.spaceID == spaceID,
              intent.desiredProfileID == targetProfile.id else {
            settlement(.rejected(.stale))
            return .stale
        }
        return execute(
            Request(
                targetProfile: targetProfile,
                tabs: tabs,
                intentsByTabID: Dictionary(
                    uniqueKeysWithValues: intent.tabIntents.map {
                        ($0.tabID, $0.intent)
                    }
                ),
                model: .transaction(ProfileTransitionModelParticipant(
                    model: model,
                    tabs: tabs
                )),
                kind: .space(intent)
            ),
            settlement: settlement
        )
    }

    private func execute(
        _ request: Request,
        settlement: @escaping Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        guard request.model.validateForStaging() else {
            settlement(.rejected(.stale))
            return .stale
        }
        let profileIDs = affectedProfileIDs(request)
        if let blocked = profileIDs.sorted(by: uuidOrder)
            .first(where: runtime.admissionIsBlocked),
           runtime.deferAdmission(blocked, request.admissionKey, { [weak self] in
               guard let self else { return }
               _ = execute(request, settlement: settlement)
           }) {
            return .deferred
        }

        let snapshots = Dictionary(uniqueKeysWithValues: request.tabs.map {
            ($0.id, runtime.webViewSessions.snapshot(for: $0.id))
        })
        let live = snapshots.filter { $0.value.allKnownWebViews.isEmpty == false }
        guard live.isEmpty == false else {
            let outcome = ProfileTransitionModelOnlySettlement.execute(
                request.model
            )
            settlement(outcome.settlement)
            return outcome.tabExecution
        }

        if let barrier = live.values.flatMap(\.allKnownWebViews)
            .filter(runtime.isProtected).min(by: identityOrder),
           let snapshot = snapshots.values.first(where: {
               $0.allKnownWebViews.contains { $0 === barrier }
           }) {
            switch runtime.deferProtectedCommand(
                request.kind.deferredCommand(snapshot), barrier, request.reason
            ) {
            case .scheduled:
                return .deferred
            case .notProtected:
                break
            case .invalidTarget, .droppedAtCapacity:
                settlement(.rejected(.failed))
                return .failed
            }
        }

        guard let prepared = runtime.provisioning.prepare(
            tabs: request.tabs,
            liveSnapshots: live,
            targetProfile: request.targetProfile,
            intentsByTabID: request.intentsByTabID,
            reason: request.reason
        ) else {
            settlement(.rejected(.failed))
            return .failed
        }

        let start = runtime.pipeline.begin(
            prepared,
            profileIDs: profileIDs,
            model: request.model,
            completion: { outcome in
                self.complete(
                    outcome,
                    request: request,
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
                reason: request.reason
            )
            return .deferred
        case .committed:
            runtime.activation.activateWithoutNavigation(
                prepared,
                reason: request.reason
            )
            return .committed
        case .conflict:
            runtime.provisioning.discard(prepared)
            retryAfterOwnershipBarrier(request, settlement: settlement)
            return .deferred
        case .stale, .modelValidationFailed:
            runtime.provisioning.discard(prepared)
            settlement(.rejected(.stale))
            return .stale
        case .invalid:
            runtime.provisioning.discard(prepared)
            settlement(.rejected(.failed))
            return .failed
        case .modelCommitFailed:
            settlement(.rejected(.stale))
            return .stale
        case .rolledBack:
            // Synchronous settlement already restored the model/repository and
            // delivered its typed rollback through `completion`.
            return .failed
        case .settlementConflict(let delivery):
            if delivery == .callerOwned { settlement(.conflicted) }
            return .failed
        case .leaseLost(let delivery):
            if delivery == .callerOwned { settlement(.leaseLost) }
            return .failed
        }
    }

    private func complete(
        _ outcome: WebViewReplacementTransactionOutcome,
        request: Request,
        prepared: [PreparedWebViewReplacement],
        settlement: @escaping Settlement
    ) {
        switch outcome {
        case .committed:
            runtime.activation.finishCommitted(prepared, reason: request.reason)
            settlement(.committed)
        case .rolledBack(let reason):
            settlement(.rolledBack(reason))
        case .conflicted:
            settlement(.conflicted)
        case .leaseLost:
            settlement(.leaseLost)
        case .abandonedForTerminalShutdown:
            settlement(.terminalShutdown)
        }
    }

    private func retryAfterOwnershipBarrier(
        _ request: Request,
        settlement: @escaping Settlement
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await runtime.webViewSessions
                .waitUntilOwnershipTransitionsAreSettled() else {
                settlement(.terminalShutdown)
                return
            }
            _ = execute(request, settlement: settlement)
        }
    }

    private func affectedProfileIDs(_ request: Request) -> Set<UUID> {
        request.tabs.reduce(into: Set([request.targetProfile.id])) { result, tab in
            if let profileID = tab.resolveProfile()?.id ?? tab.profileId {
                result.insert(profileID)
            }
        }
    }

    private func identityOrder(_ lhs: WKWebView, _ rhs: WKWebView) -> Bool {
        UInt(bitPattern: ObjectIdentifier(lhs))
            < UInt(bitPattern: ObjectIdentifier(rhs))
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
