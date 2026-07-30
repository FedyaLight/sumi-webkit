import Foundation
import SumiWebRuntime

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
