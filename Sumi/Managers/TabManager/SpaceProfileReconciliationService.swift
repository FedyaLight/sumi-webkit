import Foundation
import SumiWebRuntime

@MainActor
final class SpaceProfileReconciliationService {
    private final class SettlementBuffer {
        var isStarting = true
        var settlement: ProfileTransitionSettlement?
    }

    enum Result: Equatable {
        case noRemainingWork
        case committed
        case unavailable
        case superseded
    }

    enum Start {
        case completed(Result)
        case deferred(DeferredTransition)
    }

    struct DeferredTransition {
        fileprivate let lease: TabRuntimePortLease
        fileprivate let space: Space
        fileprivate let profileID: UUID
        fileprivate let intent: DeferredWebViewSpaceProfileAssignmentIntent
    }

    private let spaces: TabSpaceCollectionStateOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let spaceTransitions: SpaceProfileTransitionService
    private let transitionLifecycle: SpaceProfileTransitionRepository

    init(
        spaces: TabSpaceCollectionStateOwner,
        runtimeConnection: TabRuntimePortConnection,
        spaceTransitions: SpaceProfileTransitionService,
        transitionLifecycle: SpaceProfileTransitionRepository
    ) {
        self.spaces = spaces
        self.runtimeConnection = runtimeConnection
        self.spaceTransitions = spaceTransitions
        self.transitionLifecycle = transitionLifecycle
    }

    func startNext(
        using lease: TabRuntimePortLease,
        capturingTransition: ((DeferredTransition) -> Void)? = nil,
        completion: @escaping (Result) -> Void
    ) -> Start {
        guard runtimeConnection.accepts(lease) else {
            return .completed(.superseded)
        }
        guard spaces.spaces.allSatisfy({
            transitionLifecycle.hasTransaction(for: $0.id) == false
        }) else {
            return .completed(.unavailable)
        }
        guard let profileID = lease.defaultProfileID else {
            RuntimeDiagnostics.debug(
                "No profiles available for space reconciliation yet.",
                category: "SpaceProfile"
            )
            return .completed(.unavailable)
        }
        guard let space = spaces.spaces.first(where: { $0.profileId == nil }) else {
            return .completed(.noRemainingWork)
        }

        var transition: DeferredTransition?
        let buffer = SettlementBuffer()
        let outcome = spaceTransitions.start(
            spaceID: space.id,
            profileID: profileID,
            using: lease,
            capturingIntent: { intent in
                let captured = DeferredTransition(
                    lease: lease,
                    space: space,
                    profileID: profileID,
                    intent: intent
                )
                transition = captured
                capturingTransition?(captured)
            },
            settlementObserver: { [weak self, weak space] settlement in
                guard let self, let space else { return }
                if buffer.isStarting {
                    buffer.settlement = settlement
                } else {
                    completion(self.result(
                        for: settlement,
                        lease: lease,
                        space: space,
                        profileID: profileID
                    ))
                }
            }
        )
        buffer.isStarting = false

        guard runtimeConnection.accepts(lease) else {
            if let transition {
                _ = transitionLifecycle.drainForRuntimeDetach(transition.intent)
            }
            return .completed(.superseded)
        }
        if let bufferedSettlement = buffer.settlement {
            return .completed(result(
                for: bufferedSettlement,
                lease: lease,
                space: space,
                profileID: profileID
            ))
        }
        switch outcome {
        case .committed:
            return .completed(commitResult(
                lease: lease,
                space: space,
                profileID: profileID
            ))
        case .deferred:
            guard let transition else { return .completed(.unavailable) }
            return .deferred(transition)
        case .stale, .failed:
            return .completed(.unavailable)
        }
    }

    @discardableResult
    func drainForRuntimeDetach(
        _ transition: DeferredTransition
    ) -> RuntimeDetachDrainResult {
        transitionLifecycle.drainForRuntimeDetach(transition.intent)
    }

    func ownsLifecycle(of transition: DeferredTransition) -> Bool {
        transitionLifecycle.ownsLifecycle(for: transition.intent)
    }

    private func result(
        for settlement: ProfileTransitionSettlement,
        lease: TabRuntimePortLease,
        space: Space,
        profileID: UUID
    ) -> Result {
        guard runtimeConnection.accepts(lease) else { return .superseded }
        switch settlement {
        case .committed:
            return commitResult(
                lease: lease,
                space: space,
                profileID: profileID
            )
        case .rejected, .rolledBack, .conflicted:
            return .unavailable
        case .leaseLost, .terminalShutdown:
            return .superseded
        }
    }

    private func commitResult(
        lease: TabRuntimePortLease,
        space: Space,
        profileID: UUID
    ) -> Result {
        guard runtimeConnection.accepts(lease) else { return .superseded }
        guard spaces.space(with: space.id) === space,
              space.profileId == profileID else { return .unavailable }
        return .committed
    }
}
