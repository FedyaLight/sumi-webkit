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
    private let selectionContext: TabSelectionContextProjection
    lazy var selection = ProfileSelectionCoordinator(
        tabManager: tabManager,
        spaceActivation: tabManager.spaceServices.activation,
        spaceTransitions: spaces,
        selectionContext: selectionContext
    )
    lazy var deletion = ProfileDeletionMigration(
        tabManager: tabManager,
        policy: policy,
        tabTransitions: tabs,
        spaceTransitions: spaces,
        selection: selection
    )

    init(
        tabManager: TabManager,
        selectionContext: TabSelectionContextProjection
    ) {
        self.tabManager = tabManager
        self.selectionContext = selectionContext
        let policy = ProfileAssignmentPolicy(tabManager: tabManager)
        let pendingInheritance = PendingTabProfileInheritance()
        let tabs = TabProfileTransitionService(
            tabManager: tabManager,
            policy: policy,
            pendingInheritance: pendingInheritance
        )
        let spaceMutations = SpaceProfileMutationService(tabManager: tabManager)
        let spaceAdmission = SpaceProfileTransitionAdmission(
            policy: policy,
            profileMutations: spaceMutations,
            tabCandidates: SpaceProfileTabCandidatePlanner(
                membership: tabManager.tabCollectionMembershipOwner,
                registry: tabManager.liveShortcutTabs,
                pins: tabManager.shortcutPinCollectionStateOwner
            ),
            membership: tabManager.tabCollectionMembershipOwner,
            structuralLookup: tabManager.structuralLookupCoordinator
        )
        let spaces = SpaceProfileTransitionService(
            tabManager: tabManager,
            pendingInheritance: pendingInheritance,
            admission: spaceAdmission
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
