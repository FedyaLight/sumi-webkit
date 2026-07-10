import Foundation
import SumiWebRuntime

@MainActor
private final class ProfileDeletionTabIntentState {
    var intent: DeferredWebViewProfileAssignmentIntent?
}

@MainActor
private final class ProfileDeletionSpaceIntentState {
    var intent: DeferredWebViewSpaceProfileAssignmentIntent?
}

/// Composes profile-deletion policy, exact Space/Tab transitions, settlement,
/// and the final shortcut-reference mutation phase.
@MainActor
final class ProfileDeletionMigration {
    private unowned let tabManager: TabManager
    private let policy: ProfileAssignmentPolicy
    private let tabTransitions: TabProfileTransitionService
    private let spaceTransitions: SpaceProfileTransitionService
    private let selection: ProfileSelectionCoordinator
    private let referencePlanner = ShortcutProfileReferenceMutationPlanner()
    private let referenceApplicator: ShortcutProfileReferenceMutationApplicator
    private let settlement: ProfileDeletionSettlementCoordinator

    init(
        tabManager: TabManager,
        policy: ProfileAssignmentPolicy,
        tabTransitions: TabProfileTransitionService,
        spaceTransitions: SpaceProfileTransitionService,
        selection: ProfileSelectionCoordinator
    ) {
        self.tabManager = tabManager
        self.policy = policy
        self.tabTransitions = tabTransitions
        self.spaceTransitions = spaceTransitions
        self.selection = selection
        referenceApplicator = ShortcutProfileReferenceMutationApplicator(
            tabManager: tabManager
        )
        settlement = ProfileDeletionSettlementCoordinator(
            abortTransitions: { [weak tabManager] profileIDs in
                tabManager?.runtimePorts?.webViewLifecycle
                    .abortProfileTransitions(profileIDs: profileIDs) ?? 0
            }
        )
    }

    func migrate(
        deletedProfileID: UUID,
        fallbackProfileID: UUID
    ) async -> ProfileDeletionMigrationOutcome {
        guard deletedProfileID != fallbackProfileID,
              policy.profileExists(fallbackProfileID) else {
            return .rejected
        }

        let outcome = await settlement.settle(
            ProfileDeletionSettlementPlan(
                deletedProfileID: deletedProfileID,
                fallbackProfileID: fallbackProfileID,
                operations: operations(
                    deletedProfileID: deletedProfileID,
                    fallbackProfileID: fallbackProfileID
                )
            )
        )
        guard outcome == .committed else { return outcome }

        referenceApplicator.apply(
            referencePlanner.plan(
                deleting: deletedProfileID,
                state: tabManager.shortcutPinCollectionStateOwner
            )
        )
        if tabManager.runtimePorts?.currentProfileId != deletedProfileID {
            selection.handleProfileSwitch()
        }
        return .committed
    }

    private func operations(
        deletedProfileID: UUID,
        fallbackProfileID: UUID
    ) -> [ProfileDeletionOperation] {
        var result: [ProfileDeletionOperation] = []
        let spaces = tabManager.spaceStateOwner.spaces
            .filter { $0.profileId == deletedProfileID }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for space in spaces {
            let state = ProfileDeletionSpaceIntentState()
            result.append(
                ProfileDeletionOperation(
                    id: .space(space.id),
                    start: { [weak spaceTransitions] callback in
                        guard let spaceTransitions else { return .failed }
                        return spaceTransitions.start(
                            spaceID: space.id,
                            profileID: fallbackProfileID,
                            intentPrepared: { state.intent = $0 },
                            settlementObserver: callback
                        )
                    },
                    cancelPending: { [weak spaceTransitions] in
                        guard let spaceTransitions, let intent = state.intent else {
                            return
                        }
                        spaceTransitions.cancelPendingDeletionIntent(intent)
                    }
                )
            )
        }

        for tab in policy.allProfileManagedTabs().sorted(by: tabOrder) {
            guard case .assign(let desiredProfileID) = policy.deletionAssignment(
                for: tab,
                deletedProfileID: deletedProfileID,
                fallbackProfileID: fallbackProfileID
            ) else { continue }
            let state = ProfileDeletionTabIntentState()
            result.append(
                ProfileDeletionOperation(
                    id: .tab(tab.id),
                    start: { [weak tabTransitions, weak tab] callback in
                        guard let tabTransitions, let tab else { return .failed }
                        return tabTransitions.start(
                            desiredProfileID: desiredProfileID,
                            tab: tab,
                            requiresStructuralPersistence: true,
                            intentPrepared: { state.intent = $0 },
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

    private func tabOrder(_ lhs: Tab, _ rhs: Tab) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }
}
