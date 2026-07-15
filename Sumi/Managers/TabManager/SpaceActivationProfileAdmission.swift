import Foundation

/// Admits Space activation only after an unassigned target has acquired its
/// default profile. Deferred assignments retry the original activation after
/// their committed settlement arrives.
@MainActor
final class SpaceActivationProfileAdmission {
    typealias ProfileIDs = (current: UUID?, default: UUID?)

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

    private let profileIDs: @MainActor () -> ProfileIDs
    private let assignSpaceProfile: @MainActor (
        UUID,
        UUID,
        @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome

    init(
        profileIDs: @escaping @MainActor () -> ProfileIDs,
        assignSpaceProfile: @escaping @MainActor (
            UUID,
            UUID,
            @escaping ProfileTransitionService.Settlement
        ) -> TabProfileAssignmentExecutionOutcome
    ) {
        self.profileIDs = profileIDs
        self.assignSpaceProfile = assignSpaceProfile
    }

    var currentProfileID: UUID? {
        profileIDs().current
    }

    func admit(
        _ space: Space,
        retry: @escaping @MainActor () -> Void
    ) -> Bool {
        guard space.profileId == nil else { return true }
        guard let profileID = profileIDs().default else {
            RuntimeDiagnostics.debug(
                "No profiles available to assign to a space switch target; reconciliation deferred.",
                category: "SpaceActivation"
            )
            return false
        }

        let handoff = AssignmentHandoff(retry: retry)
        let outcome = assignSpaceProfile(space.id, profileID) { settlement in
            handoff.receive(settlement)
        }
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
