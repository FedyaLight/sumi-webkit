import Foundation

/// Composition-only profile subsystem. Behavior lives in the focused
/// services; this type exposes no forwarding façade.
@MainActor
final class ProfileAssignmentServices {
    let policy: ProfileAssignmentPolicy
    let tabs: TabProfileTransitionService
    let spaces: SpaceProfileTransitionService
    let shortcuts: ShortcutExecutionProfileAssignmentService
    let selection: ProfileSelectionCoordinator
    let deletion: ProfileDeletionMigration

    init(tabManager: TabManager) {
        let policy = ProfileAssignmentPolicy(tabManager: tabManager)
        let tabs = TabProfileTransitionService(
            tabManager: tabManager,
            policy: policy
        )
        let spaces = SpaceProfileTransitionService(
            tabManager: tabManager,
            policy: policy
        )
        let selection = ProfileSelectionCoordinator(tabManager: tabManager)

        self.policy = policy
        self.tabs = tabs
        self.spaces = spaces
        shortcuts = ShortcutExecutionProfileAssignmentService(
            tabManager: tabManager,
            policy: policy
        )
        self.selection = selection
        deletion = ProfileDeletionMigration(
            tabManager: tabManager,
            policy: policy,
            tabTransitions: tabs,
            spaceTransitions: spaces,
            selection: selection
        )
    }
}
