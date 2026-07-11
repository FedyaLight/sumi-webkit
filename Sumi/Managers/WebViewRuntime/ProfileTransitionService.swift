import Foundation
import WebKit
import SumiWebRuntime

enum ProfileTransitionSettlement: Equatable {
    case committed
    case rejected(TabProfileAssignmentExecutionOutcome)
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

    private struct Request {
        let targetProfile: Profile
        let tabs: [Tab]
        let validateModel: @MainActor @Sendable () -> Bool
        let stageModel: @MainActor @Sendable () throws -> Void
        let finishModel: () -> Void
        let rollbackModel: () throws -> Void
        let deferredCommand: (WebViewSessionSnapshot) -> DeferredWebViewCommand
        let admissionKey: WebsiteDataMutationGate.DeferredAdmissionKey
        let reason: String
    }

    private enum ModelError: Error { case rejected }

    private let runtime: Runtime

    init(runtime: Runtime) {
        self.runtime = runtime
    }

    func transition(
        tab: Tab,
        to targetProfile: Profile,
        intent: DeferredWebViewProfileAssignmentIntent,
        settlement: @escaping Settlement = { _ in }
    ) -> TabProfileAssignmentExecutionOutcome {
        execute(
            Request(
                targetProfile: targetProfile,
                tabs: [tab],
                validateModel: {
                    intent.resolvedProfileID == targetProfile.id
                        && tab.profileAssignment.isCurrent(intent)
                },
                stageModel: {
                    guard tab.profileAssignment.stage(intent) else {
                        throw ModelError.rejected
                    }
                },
                finishModel: {
                    precondition(
                        tab.profileAssignment.finish(intent),
                        "Profile transition lost its staged Tab intent"
                    )
                },
                rollbackModel: {
                    guard tab.profileAssignment.rollback(intent) else {
                        throw ModelError.rejected
                    }
                },
                deferredCommand: { snapshot in
                    .assignProfile(
                        tabID: tab.id,
                        preferredPrimaryWindowID: snapshot.primaryWindowID,
                        intent: intent
                    )
                },
                admissionKey: .profileAssignment(tabID: tab.id),
                reason: "profile-assignment"
            ),
            settlement: settlement
        )
    }

    func transition(
        spaceID: UUID,
        to targetProfile: Profile,
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        tabsByID: [UUID: Tab],
        validateModel: @escaping @MainActor @Sendable () -> Bool,
        stageModel: @escaping @MainActor @Sendable () -> Bool,
        finishModel: @escaping () -> Void,
        rollbackModel: @escaping () -> Void,
        settlement: @escaping Settlement = { _ in }
    ) -> TabProfileAssignmentExecutionOutcome {
        let tabs = intent.tabIntents.compactMap { tabsByID[$0.tabID] }
        guard tabs.count == intent.tabIntents.count,
              intent.spaceID == spaceID,
              intent.desiredProfileID == targetProfile.id else {
            settlement(.rejected(.stale))
            return .stale
        }
        return execute(
            Request(
                targetProfile: targetProfile,
                tabs: tabs,
                validateModel: validateModel,
                stageModel: {
                    guard stageModel() else { throw ModelError.rejected }
                },
                finishModel: finishModel,
                rollbackModel: rollbackModel,
                deferredCommand: { _ in .assignSpaceProfile(intent: intent) },
                admissionKey: .spaceProfileAssignment(spaceID: spaceID),
                reason: "space-profile-assignment"
            ),
            settlement: settlement
        )
    }

    private func execute(
        _ request: Request,
        settlement: @escaping Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        guard request.validateModel() else {
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
            do {
                try request.stageModel()
                request.tabs.forEach { _ = $0.beginWebViewRebuildIntent() }
                request.finishModel()
                settlement(.committed)
                return .committed
            } catch {
                settlement(.rejected(.stale))
                return .stale
            }
        }

        if let barrier = live.values.flatMap(\.allKnownWebViews)
            .filter(runtime.isProtected).min(by: identityOrder),
           let snapshot = snapshots.values.first(where: {
               $0.allKnownWebViews.contains { $0 === barrier }
           }) {
            switch runtime.deferProtectedCommand(
                request.deferredCommand(snapshot), barrier, request.reason
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
            reason: request.reason
        ) else {
            settlement(.rejected(.failed))
            return .failed
        }

        let start = runtime.pipeline.begin(
            prepared,
            profileIDs: profileIDs,
            validateModel: request.validateModel,
            modelCommit: {
                try request.stageModel()
                request.tabs.forEach { _ = $0.beginWebViewRebuildIntent() }
            },
            modelRollback: {
                try request.rollbackModel()
            },
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
        case .stale, .modelCommitFailed:
            runtime.provisioning.discard(prepared)
            settlement(.rejected(.stale))
            return .stale
        case .invalid:
            runtime.provisioning.discard(prepared)
            settlement(.rejected(.failed))
            return .failed
        case .rolledBack:
            // Synchronous settlement already restored the model/repository and
            // delivered its typed rollback through `completion`.
            return .failed
        case .settlementConflict:
            settlement(.conflicted)
            return .failed
        case .leaseLost:
            settlement(.leaseLost)
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
            request.finishModel()
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
