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

@MainActor
final class ProfileSpaceRetirementService {
    private let spaces: TabSpaceCollectionStateOwner
    private let catalog: SpaceCatalogCommands
    private let removal: SpaceRemovalService
    private let transitions: SpaceProfileTransitionRepository

    init(
        spaces: TabSpaceCollectionStateOwner,
        catalog: SpaceCatalogCommands,
        removal: SpaceRemovalService,
        transitions: SpaceProfileTransitionRepository
    ) {
        self.spaces = spaces
        self.catalog = catalog
        self.removal = removal
        self.transitions = transitions
    }

    func ensureFallbackSpace(for profileID: UUID) -> Bool {
        catalog.ensureProfileRetirementFallbackSpace(profileID: profileID)
    }

    func retireSpaces(ownedBy profileID: UUID) -> Bool {
        guard transitions.containsReference(to: profileID) == false else {
            return false
        }
        let spaceIDs = spaces.spaces
            .filter { $0.profileId == profileID }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
        guard spaceIDs.isEmpty
                || removal.removeSpacesForProfileRetirement(spaceIDs) else {
            return false
        }
        return containsReference(to: profileID) == false
    }

    func containsReference(to profileID: UUID) -> Bool {
        spaces.spaces.contains { $0.profileId == profileID }
            || transitions.containsReference(to: profileID)
    }
}

/// Composes exact profile-deletion operations, settlement, and finalization.
@MainActor
final class ProfileDeletionMigration {
    private let policy: ProfileAssignmentPolicy
    private let runtimeConnection: TabRuntimePortConnection
    private let spaces: ProfileSpaceRetirementService
    private let operations: ProfileDeletionOperationPlanner
    private let settlement: ProfileDeletionSettlementCoordinator
    private let shortcutReferences: ShortcutProfileReferenceRetirementService
    private let selection: ProfileSelectionCoordinator

    init(
        policy: ProfileAssignmentPolicy,
        runtimeConnection: TabRuntimePortConnection,
        spaces: ProfileSpaceRetirementService,
        operations: ProfileDeletionOperationPlanner,
        settlement: ProfileDeletionSettlementCoordinator,
        shortcutReferences: ShortcutProfileReferenceRetirementService,
        selection: ProfileSelectionCoordinator
    ) {
        self.policy = policy
        self.runtimeConnection = runtimeConnection
        self.spaces = spaces
        self.operations = operations
        self.settlement = settlement
        self.shortcutReferences = shortcutReferences
        self.selection = selection
    }

    func ensureFallbackSpace(for profileID: UUID) -> Bool {
        spaces.ensureFallbackSpace(for: profileID)
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
        guard outcome == .committed else {
            return outcome
        }

        guard runtimeConnection.acceptsExactAttachment(runtimeLease),
              operations.containsTabReference(
                  to: deletedProfileID,
                  fallbackProfileID: fallbackProfileID,
                  using: runtimeLease
              ) == false,
              runtimeConnection.acceptsExactAttachment(runtimeLease) else {
            return .rejected
        }

        guard shortcutReferences.migrate(
            deletedProfileID: deletedProfileID,
            fallbackProfileID: fallbackProfileID,
            using: runtimeLease
        ) else {
            return .rejected
        }
        guard runtimeConnection.acceptsExactAttachment(runtimeLease),
              operations.containsTabReference(
                  to: deletedProfileID,
                  fallbackProfileID: fallbackProfileID,
                  using: runtimeLease
              ) == false,
              shortcutReferences.containsReference(
                  to: deletedProfileID
              ) == false,
              spaces.retireSpaces(ownedBy: deletedProfileID),
              runtimeConnection.acceptsExactAttachment(runtimeLease),
              spaces.containsReference(to: deletedProfileID) == false,
              operations.containsTabReference(
                  to: deletedProfileID,
                  fallbackProfileID: fallbackProfileID,
                  using: runtimeLease
              ) == false,
              shortcutReferences.containsReference(
                  to: deletedProfileID
              ) == false,
              runtimeConnection.acceptsExactAttachment(runtimeLease) else {
            return .rejected
        }
        if runtimeLease.currentProfileID != deletedProfileID {
            selection.handleProfileSwitch()
        }
        return .committed
    }

    func containsReference(to profileID: UUID) -> Bool {
        let runtimeLease = runtimeConnection.captureLease()
        guard runtimeConnection.acceptsExactAttachment(runtimeLease),
              spaces.containsReference(to: profileID) == false,
              operations.containsReference(to: profileID) == false,
              shortcutReferences.containsReference(to: profileID) == false,
              runtimeConnection.acceptsExactAttachment(runtimeLease)
        else {
            return true
        }
        return false
    }
}
