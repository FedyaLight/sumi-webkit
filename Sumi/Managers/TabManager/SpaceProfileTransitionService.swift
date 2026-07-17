import Foundation
import SumiWebRuntime

@MainActor
final class SpaceProfileTransitionService {
    private let runtimeConnection: TabRuntimePortConnection
    private let admission: SpaceProfileTransitionAdmission
    private let repository: SpaceProfileTransitionRepository

    init(
        runtimeConnection: TabRuntimePortConnection,
        admission: SpaceProfileTransitionAdmission,
        repository: SpaceProfileTransitionRepository
    ) {
        self.runtimeConnection = runtimeConnection
        self.admission = admission
        self.repository = repository
    }

    var lifecycle: SpaceProfileTransitionRepository { repository }

    func isCurrent(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool {
        repository.isCurrent(intent)
    }

    @discardableResult
    func start(
        spaceID: UUID,
        profileID: UUID,
        using runtimeLease: TabRuntimePortLease? = nil,
        capturingIntent: ((
            DeferredWebViewSpaceProfileAssignmentIntent
        ) -> Void)? = nil,
        settlementObserver: ProfileTransitionService.Settlement? = nil
    ) -> TabProfileAssignmentExecutionOutcome {
        let runtimeLease = runtimeLease ?? runtimeConnection.captureLease()
        guard runtimeConnection.accepts(runtimeLease),
              let space = repository.space(with: spaceID),
              repository.hasTransaction(for: spaceID) == false else {
            return .failed
        }
        guard space.profileId != profileID else { return .committed }
        let revision = repository.nextRevision(for: spaceID)
        guard let transaction = admission.prepare(
            space: space,
            targetProfileID: profileID,
            revision: revision,
            using: runtimeLease,
            connection: runtimeConnection
        ) else { return .failed }
        guard repository.install(
            transaction,
            observer: settlementObserver
        ) else {
            transaction.abortPending()
            return .failed
        }
        let intent = transaction.intent
        capturingIntent?(intent)
        guard runtimeConnection.accepts(runtimeLease) else {
            repository.receive(.leaseLost, intent: intent)
            return .stale
        }

        let outcome = execute(
            space: space,
            profile: transaction.targetProfile,
            intent: intent,
            using: runtimeLease
        )
        if let settlement = outcome.immediateSettlement {
            repository.receive(settlement, intent: intent)
        }
        return outcome
    }

    @discardableResult
    func executeDeferred(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool {
        guard let transaction = repository.transaction(for: intent),
              transaction.isCurrentPending(revision: intent.revision) else {
            return rejectDeferred(.rejected(.stale), intent: intent)
        }
        let runtimeLease = transaction.runtimeLease
        guard runtimeConnection.accepts(runtimeLease),
              let runtime = runtimeLease.registry else {
            return rejectDeferred(.leaseLost, intent: intent)
        }
        let space = repository.space(with: intent.spaceID)
        let profile = runtime.profile(with: intent.desiredProfileID)
        guard runtimeConnection.accepts(runtimeLease) else {
            return rejectDeferred(.leaseLost, intent: intent)
        }
        guard let space, let profile,
              profile.id == intent.desiredProfileID else {
            return rejectDeferred(.rejected(.stale), intent: intent)
        }
        return execute(
            space: space,
            profile: profile,
            intent: intent,
            using: runtimeLease
        ).wasAccepted
    }

    private func rejectDeferred(
        _ settlement: ProfileTransitionSettlement,
        intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool {
        repository.receive(settlement, intent: intent)
        return false
    }

    private func execute(
        space: Space,
        profile: Profile,
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        using runtimeLease: TabRuntimePortLease
    ) -> TabProfileAssignmentExecutionOutcome {
        guard runtimeConnection.accepts(runtimeLease),
              let lifecycle = runtimeLease.registry?.webViewLifecycle else {
            repository.receive(.leaseLost, intent: intent)
            return .failed
        }
        guard let transaction = repository.transaction(for: intent) else {
            repository.receive(.rejected(.stale), intent: intent)
            return .stale
        }
        let model = SpaceProfileReplacementModelParticipant(
            transaction: transaction,
            owner: repository
        )
        let outcome = lifecycle.executeSpaceProfileAssignment(
            space: space,
            targetProfile: profile,
            intent: intent,
            model: model,
            settlement: { [weak repository] settlement in
                repository?.receive(settlement, intent: intent)
            }
        )
        guard runtimeConnection.accepts(runtimeLease) else {
            repository.receive(.leaseLost, intent: intent)
            return .stale
        }
        return outcome
    }
}
