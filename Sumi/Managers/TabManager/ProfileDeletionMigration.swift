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

@MainActor
final class ProfileDeletionOperationPlanner {
    private let spaces: TabSpaceCollectionStateOwner
    private let policy: ProfileAssignmentPolicy
    private let tabTransitions: TabProfileTransitionService
    private let spaceTransitions: SpaceProfileTransitionService
    private let spaceTransitionLifecycle: SpaceProfileTransitionRepository

    init(
        spaces: TabSpaceCollectionStateOwner,
        policy: ProfileAssignmentPolicy,
        tabTransitions: TabProfileTransitionService,
        spaceTransitions: SpaceProfileTransitionService,
        spaceTransitionLifecycle: SpaceProfileTransitionRepository
    ) {
        self.spaces = spaces
        self.policy = policy
        self.tabTransitions = tabTransitions
        self.spaceTransitions = spaceTransitions
        self.spaceTransitionLifecycle = spaceTransitionLifecycle
    }

    func operations(
        deletedProfileID: UUID,
        fallbackProfileID: UUID,
        using runtimeLease: TabRuntimePortLease
    ) -> [ProfileDeletionOperation] {
        var result: [ProfileDeletionOperation] = []
        let candidateSpaces = spaces.spaces
            .filter { $0.profileId == deletedProfileID }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for space in candidateSpaces {
            let state = ProfileDeletionSpaceIntentState()
            result.append(
                ProfileDeletionOperation(
                    id: .space(space.id),
                    start: { [weak spaceTransitions] callback in
                        guard let spaceTransitions else { return .failed }
                        return spaceTransitions.start(
                            spaceID: space.id,
                            profileID: fallbackProfileID,
                            using: runtimeLease,
                            capturingIntent: { state.intent = $0 },
                            settlementObserver: callback
                        )
                    },
                    cancelPending: { [weak spaceTransitionLifecycle] in
                        guard let spaceTransitionLifecycle,
                              let intent = state.intent else {
                            return
                        }
                        spaceTransitionLifecycle.cancelPending(intent)
                    }
                )
            )
        }

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
                    id: .tab(tab.id),
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

    func containsTabOrSpaceReference(
        to deletedProfileID: UUID,
        fallbackProfileID: UUID,
        using runtimeLease: TabRuntimePortLease
    ) -> Bool {
        if spaces.spaces.contains(where: {
            $0.profileId == deletedProfileID
                || spaceTransitionLifecycle.inFlightProfileID(for: $0.id)
                == deletedProfileID
        }) {
            return true
        }
        return policy.allProfileManagedTabs().contains { tab in
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

    private func tabOrder(_ lhs: Tab, _ rhs: Tab) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }
}

@MainActor
final class ProfileDeletionFinalizer {
    private let pins: ShortcutPinCollectionStateOwner
    private let references: ShortcutProfileReferenceMutationApplicator
    private let runtimeConnection: TabRuntimePortConnection
    private let selection: ProfileSelectionCoordinator

    init(
        pins: ShortcutPinCollectionStateOwner,
        references: ShortcutProfileReferenceMutationApplicator,
        runtimeConnection: TabRuntimePortConnection,
        selection: ProfileSelectionCoordinator
    ) {
        self.pins = pins
        self.references = references
        self.runtimeConnection = runtimeConnection
        self.selection = selection
    }

    func finish(
        deletedProfileID: UUID,
        using runtimeLease: TabRuntimePortLease
    ) -> Bool {
        guard runtimeConnection.acceptsExactAttachment(runtimeLease) else {
            return false
        }
        guard references.apply(
            ShortcutProfileReferenceMutationPlanner().plan(
                deleting: deletedProfileID,
                state: pins
            ),
            using: runtimeLease
        ) else { return false }
        if runtimeConnection.acceptsExactAttachment(runtimeLease),
           runtimeLease.currentProfileID != deletedProfileID {
            selection.handleProfileSwitch()
        }
        return containsShortcutReference(to: deletedProfileID) == false
    }

    private func containsShortcutReference(to profileID: UUID) -> Bool {
        let profilePins = pins.pinnedByProfileSnapshot()
        if profilePins[profileID] != nil {
            return true
        }
        if profilePins.values.joined().contains(where: {
            $0.executionProfileId == profileID
        }) {
            return true
        }
        return pins.spacePinnedShortcutsSnapshot().values.joined().contains {
            $0.executionProfileId == profileID
        }
    }
}

/// Composes exact profile-deletion operations, settlement, and finalization.
@MainActor
final class ProfileDeletionMigration {
    private let policy: ProfileAssignmentPolicy
    private let runtimeConnection: TabRuntimePortConnection
    private let operations: ProfileDeletionOperationPlanner
    private let settlement: ProfileDeletionSettlementCoordinator
    private let finalizer: ProfileDeletionFinalizer

    init(
        policy: ProfileAssignmentPolicy,
        runtimeConnection: TabRuntimePortConnection,
        operations: ProfileDeletionOperationPlanner,
        settlement: ProfileDeletionSettlementCoordinator,
        finalizer: ProfileDeletionFinalizer
    ) {
        self.policy = policy
        self.runtimeConnection = runtimeConnection
        self.operations = operations
        self.settlement = settlement
        self.finalizer = finalizer
    }

    func migrate(
        deletedProfileID: UUID,
        fallbackProfileID: UUID
    ) async -> ProfileDeletionMigrationOutcome {
        let runtimeLease = runtimeConnection.captureLease()
        guard deletedProfileID != fallbackProfileID,
              runtimeConnection.acceptsExactAttachment(runtimeLease),
              policy.profileExists(fallbackProfileID, using: runtimeLease),
              runtimeConnection.acceptsExactAttachment(runtimeLease) else {
            return .rejected
        }

        let outcome = await settlement.settle(
            ProfileDeletionSettlementPlan(
                deletedProfileID: deletedProfileID,
                fallbackProfileID: fallbackProfileID,
                operations: operations.operations(
                    deletedProfileID: deletedProfileID,
                    fallbackProfileID: fallbackProfileID,
                    using: runtimeLease
                ),
                abortTransitions: { [runtimeConnection] profileIDs in
                    guard runtimeConnection.acceptsExactAttachment(
                        runtimeLease
                    ), let lifecycle = runtimeLease.registry?.webViewLifecycle
                    else { return 0 }
                    let aborted = lifecycle.abortProfileTransitions(
                        profileIDs: profileIDs
                    )
                    return runtimeConnection.acceptsExactAttachment(
                        runtimeLease
                    ) ? aborted : 0
                }
            )
        )
        guard outcome == .committed else { return outcome }

        guard runtimeConnection.acceptsExactAttachment(runtimeLease),
              operations.containsTabOrSpaceReference(
                  to: deletedProfileID,
                  fallbackProfileID: fallbackProfileID,
                  using: runtimeLease
              ) == false,
              runtimeConnection.acceptsExactAttachment(runtimeLease) else {
            return .rejected
        }

        guard finalizer.finish(
            deletedProfileID: deletedProfileID,
            using: runtimeLease
        ) else { return .rejected }
        guard runtimeConnection.acceptsExactAttachment(runtimeLease),
              operations.containsTabOrSpaceReference(
                  to: deletedProfileID,
                  fallbackProfileID: fallbackProfileID,
                  using: runtimeLease
              ) == false,
              runtimeConnection.acceptsExactAttachment(runtimeLease) else {
            return .rejected
        }
        return .committed
    }
}
