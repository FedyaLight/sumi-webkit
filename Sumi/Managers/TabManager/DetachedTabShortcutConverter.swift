import Foundation
import SumiDomain
import SumiWebRuntime

/// Replaces a regular tab that is not displayed by any browser window with a
/// durable shortcut definition. It deliberately creates no live shortcut tab;
/// a window materializes one later when the launcher is activated.
@MainActor
final class DetachedTabShortcutConverter {
    private let batches: ShortcutTabBindingBatchFactory
    private let windows: ShortcutTabWindowQuery
    private let containerRemoval: ShortcutContainerRemovalOwner
    private let membership: TabCollectionMembershipOwner
    private let selection: TabSelectionStateOwner
    private let runtimeTeardown: TabRuntimeTeardownService
    private let windowReconciler: RegularTabShortcutWindowReconciler

    init(
        batches: ShortcutTabBindingBatchFactory,
        windows: ShortcutTabWindowQuery,
        containerRemoval: ShortcutContainerRemovalOwner,
        membership: TabCollectionMembershipOwner,
        selection: TabSelectionStateOwner,
        runtimeTeardown: TabRuntimeTeardownService,
        windowReconciler: RegularTabShortcutWindowReconciler
    ) {
        self.batches = batches
        self.windows = windows
        self.containerRemoval = containerRemoval
        self.membership = membership
        self.selection = selection
        self.runtimeTeardown = runtimeTeardown
        self.windowReconciler = windowReconciler
    }

    convenience init(tabManager: TabManager) {
        self.init(
            batches: ShortcutTabBindingBatchFactory(
                runtimeConnection: tabManager.runtimePortConnection,
                windowMutations: tabManager.shortcutWindowMutationOwner,
                profiles: tabManager.profileAssignments.tabs,
                persistence: ShortcutSplitLauncherWindowPersistence(
                    structuralLookup: tabManager.structuralLookupCoordinator
                ),
                structuralLookup: tabManager.structuralLookupCoordinator
            ),
            windows: tabManager.shortcutTabWindowQuery,
            containerRemoval: tabManager.shortcutContainerRemovalOwner,
            membership: tabManager.tabCollectionMembershipOwner,
            selection: tabManager.selectionStateOwner,
            runtimeTeardown: tabManager.runtimeTeardown,
            windowReconciler: RegularTabShortcutWindowReconciler(
                regularTabs: tabManager.regularTabCollectionOwner
            )
        )
    }

    func beginBindingBatch(
        using attachment: TabRuntimeAttachmentWitness
    ) -> ShortcutTabBindingBatchBuilder {
        batches.make(using: attachment)
    }

    func prepare(
        transition: RegularTabShortcutWindowTransitionPlan,
        using authorization: AuthorizedDetachedTabShortcutConversion
    ) -> PreparedDetachedTabShortcutTransition? {
        guard let source = DetachedTabShortcutSourceModelTransaction(
            tab: authorization.tab,
            container: containerRemoval,
            membership: membership,
            selection: selection
        ) else { return nil }
        guard let exposure = DetachedTabRuntimeExposureWitness(
            tab: authorization.tab,
            attachment: authorization.runtimeAttachment,
            windows: windows
        ) else { return nil }
        guard let terminal = DetachedTabTerminalRetirementPublisher(
            tab: authorization.tab,
            source: source,
            exposure: exposure,
            teardown: runtimeTeardown
        ) else { return nil }
        let windows = authorization.runtime.flatMap {
            windowReconciler.prepareContribution(
                originalTabId: authorization.tab.id,
                splitTransition: transition,
                sourceSpaceId: authorization.tab.spaceId,
                liveTabsByWindowId: [:],
                terminalIdentitiesByWindowId: [:],
                selectedWindowIds: [],
                using: $0
            )
        } ?? .empty
        let runtime = DetachedTabRuntimeRetirementParticipant(
            source: source,
            exposure: exposure,
            terminal: terminal
        )
        guard runtime.validateForStaging() else { return nil }
        return PreparedDetachedTabShortcutTransition(
            windows: windows,
            runtime: runtime
        )
    }
}

@MainActor
struct PreparedDetachedTabShortcutTransition {
    let windows: ShortcutTabBindingWindowContribution
    let runtime: DetachedTabRuntimeRetirementParticipant
}
