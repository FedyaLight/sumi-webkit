import Foundation

/// Composition-only profile subsystem. Behavior lives in the focused
/// services; this type exposes no forwarding façade.
@MainActor
final class ProfileAssignmentServices {
    private unowned let tabManager: TabManager

    let policy: ProfileAssignmentPolicy
    let tabs: TabProfileTransitionService
    let spaces: SpaceProfileTransitionService
    let shortcuts: ShortcutExecutionProfileAssignmentService
    lazy var selection = ProfileSelectionCoordinator(
        tabManager: tabManager,
        spaceActivation: tabManager.spaceServices.activation
    )
    lazy var deletion = ProfileDeletionMigration(
        tabManager: tabManager,
        policy: policy,
        tabTransitions: tabs,
        spaceTransitions: spaces,
        selection: selection
    )

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        let policy = ProfileAssignmentPolicy(tabManager: tabManager)
        let pendingInheritance = PendingTabProfileInheritance()
        let tabs = TabProfileTransitionService(
            tabManager: tabManager,
            policy: policy,
            pendingInheritance: pendingInheritance
        )
        let spaces = SpaceProfileTransitionService(
            tabManager: tabManager,
            policy: policy,
            pendingInheritance: pendingInheritance
        )

        self.policy = policy
        self.tabs = tabs
        self.spaces = spaces
        shortcuts = ShortcutExecutionProfileAssignmentService(
            tabManager: tabManager,
            policy: policy
        )
    }
}
