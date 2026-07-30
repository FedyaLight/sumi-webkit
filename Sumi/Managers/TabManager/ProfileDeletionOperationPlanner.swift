import Foundation
import SumiWebRuntime


@MainActor
private final class ProfileDeletionTabIntentState {
    var intent: DeferredWebViewProfileAssignmentIntent?
}
@MainActor
final class ProfileDeletionOperationPlanner {
    private let policy: ProfileAssignmentPolicy
    private let tabTransitions: TabProfileTransitionService

    init(
        policy: ProfileAssignmentPolicy,
        tabTransitions: TabProfileTransitionService
    ) {
        self.policy = policy
        self.tabTransitions = tabTransitions
    }

    func operations(
        deletedProfileID: UUID,
        fallbackProfileID: UUID,
        using runtimeLease: TabRuntimePortLease
    ) -> [ProfileDeletionOperation] {
        var result: [ProfileDeletionOperation] = []
        for tab in policy.allProfileManagedTabs().sorted(by: tabOrder) {
            guard case .assign(let desiredProfileID) = policy.deletionAssignment(
                for: tab,
                deletedProfileID: deletedProfileID,
                fallbackProfileID: fallbackProfileID,
                using: runtimeLease
            ) else { continue }
            let state = ProfileDeletionTabIntentState()
            result.append(
                ProfileDeletionOperation(
                    id: tab.id,
                    start: { [weak tabTransitions, weak tab] callback in
                        guard let tabTransitions, let tab else { return .failed }
                        return tabTransitions.start(
                            desiredProfileID: desiredProfileID,
                            tab: tab,
                            requiresStructuralPersistence: true,
                            using: runtimeLease,
                            capturingIntent: { state.intent = $0 },
                            settlementObserver: callback
                        )
                    },
                    cancelPending: { [weak tabTransitions, weak tab] in
                        guard let tabTransitions, let tab,
                              let intent = state.intent else { return }
                        tabTransitions.cancelPendingDeletionIntent(
                            tab: tab,
                            intent: intent
                        )
                    }
                )
            )
        }
        return result
    }

    func containsTabReference(
        to deletedProfileID: UUID,
        fallbackProfileID: UUID,
        using runtimeLease: TabRuntimePortLease
    ) -> Bool {
        policy.allProfileManagedTabs().contains { tab in
            if tab.profileAssignment.hasPendingAssignment(
                to: deletedProfileID
            ) {
                return true
            }
            return policy.deletionAssignment(
                for: tab,
                deletedProfileID: deletedProfileID,
                fallbackProfileID: fallbackProfileID,
                using: runtimeLease
            ) != .none
        }
    }

    func containsReference(to profileID: UUID) -> Bool {
        policy.allProfileManagedTabs().contains { tab in
            tab.profileId == profileID
                || tab.profileAssignment.hasPendingAssignment(to: profileID)
                || tab.profileAssignment.hasPendingResolvedAssignment(
                    to: profileID
                )
        }
    }

    private func tabOrder(_ lhs: Tab, _ rhs: Tab) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }
}
