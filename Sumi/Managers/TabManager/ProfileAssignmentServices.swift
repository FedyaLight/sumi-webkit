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

    init(
        policy: ProfileAssignmentPolicy,
        tabs: TabProfileTransitionService,
        spaces: SpaceProfileTransitionService,
        shortcuts: ShortcutExecutionProfileAssignmentService,
        selection: ProfileSelectionCoordinator,
        deletion: ProfileDeletionMigration
    ) {
        self.policy = policy
        self.tabs = tabs
        self.spaces = spaces
        self.shortcuts = shortcuts
        self.selection = selection
        self.deletion = deletion
    }
}
