import Foundation

/// Admits Space activation only after an unassigned target has acquired its
/// default profile. Deferred assignments retry the original activation after
/// their committed settlement arrives.
@MainActor
final class SpaceActivationProfileAdmission {
    @MainActor
    private final class AssignmentHandoff {
        private let retry: @MainActor () -> Void
        private var assignmentReturned = false
        private(set) var synchronousSettlement: ProfileTransitionSettlement?

        init(retry: @escaping @MainActor () -> Void) {
            self.retry = retry
        }

        func receive(_ settlement: ProfileTransitionSettlement) {
            guard assignmentReturned else {
                synchronousSettlement = settlement
                return
            }
            if settlement == .committed {
                retry()
            }
        }

        func markAssignmentReturned() {
            assignmentReturned = true
        }
    }

    private let runtimeConnection: TabRuntimePortConnection
    private let profileTransitions: SpaceProfileTransitionService

    init(
        runtimeConnection: TabRuntimePortConnection,
        profileTransitions: SpaceProfileTransitionService
    ) {
        self.runtimeConnection = runtimeConnection
        self.profileTransitions = profileTransitions
    }

    var currentProfileID: UUID? {
        runtimeConnection.captureLease().currentProfileID
    }

    func admit(
        _ space: Space,
        retry: @escaping @MainActor () -> Void
    ) -> Bool {
        guard space.profileId == nil else { return true }
        let runtimeLease = runtimeConnection.captureLease()
        guard let profileID = runtimeLease.defaultProfileID else {
            RuntimeDiagnostics.debug(
                "No profiles available to assign to a space switch target; reconciliation deferred.",
                category: "SpaceActivation"
            )
            return false
        }

        let handoff = AssignmentHandoff(retry: retry)
        guard runtimeConnection.acceptsExactAttachment(runtimeLease) else {
            return false
        }
        let outcome = profileTransitions.start(
            spaceID: space.id,
            profileID: profileID,
            settlementObserver: handoff.receive
        )
        handoff.markAssignmentReturned()

        switch outcome {
        case .committed:
            return space.profileId == profileID
        case .deferred:
            if handoff.synchronousSettlement == .committed {
                return space.profileId == profileID
            }
            return false
        case .failed, .stale:
            return false
        }
    }
}
