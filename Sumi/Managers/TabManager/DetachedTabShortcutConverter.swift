import Foundation
import SumiDomain
import SumiWebRuntime

/// Replaces a regular tab that is not displayed by any browser window with a
/// durable shortcut definition. It deliberately creates no live shortcut tab;
/// a window materializes one later when the launcher is activated.
@MainActor
final class DetachedTabShortcutConverter {
    private let regularTabs: RegularTabCollectionOwner
    private let containerRemoval: ShortcutContainerRemovalOwner
    private let membership: TabCollectionMembershipOwner
    private let selection: TabSelectionStateOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let runtimeTeardown: TabRuntimeTeardownService
    private let windowReconciler: RegularTabShortcutWindowReconciler

    init(
        regularTabs: RegularTabCollectionOwner,
        containerRemoval: ShortcutContainerRemovalOwner,
        membership: TabCollectionMembershipOwner,
        selection: TabSelectionStateOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeTeardown: TabRuntimeTeardownService,
        windowMutations: BrowserWindowShortcutMutationOwner
    ) {
        self.regularTabs = regularTabs
        self.containerRemoval = containerRemoval
        self.membership = membership
        self.selection = selection
        self.structuralLookup = structuralLookup
        self.runtimeTeardown = runtimeTeardown
        windowReconciler = RegularTabShortcutWindowReconciler(
            regularTabs: regularTabs,
            windowMutations: windowMutations
        )
    }

    convenience init(tabManager: TabManager) {
        self.init(
            regularTabs: tabManager.regularTabCollectionOwner,
            containerRemoval: tabManager.shortcutContainerRemovalOwner,
            membership: tabManager.tabCollectionMembershipOwner,
            selection: tabManager.selectionStateOwner,
            structuralLookup: tabManager.structuralLookupCoordinator,
            runtimeTeardown: tabManager.runtimeTeardown,
            windowMutations: tabManager.shortcutWindowMutationOwner
        )
    }

    func prepare(
        transition: RegularTabShortcutWindowTransitionPlan,
        using authorization: AuthorizedDetachedTabShortcutConversion,
        participants: RegularTabShortcutCommitParticipants
    ) -> DetachedTabShortcutConversionReceipt? {
        DetachedTabShortcutConversionReceipt(
            transition: transition,
            authorization: authorization,
            participants: participants,
            regularTabs: regularTabs,
            containerRemoval: containerRemoval,
            membership: membership,
            selection: selection,
            structuralLookup: structuralLookup,
            runtimeTeardown: runtimeTeardown,
            windowReconciler: windowReconciler
        )
    }
}
