import Foundation
import SumiDomain

/// Applies the admitted runtime half of an authorized displayed conversion.
@MainActor
final class DisplayedTabShortcutConversionCommitter {
    private let materializer: ShortcutTabMaterializer
    private let containerRemoval: ShortcutContainerRemovalOwner
    private let adopter: ShortcutTabAdopter
    private let windowReconciler: RegularTabShortcutWindowReconciler
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        materializer: ShortcutTabMaterializer,
        containerRemoval: ShortcutContainerRemovalOwner,
        adopter: ShortcutTabAdopter,
        regularTabs: RegularTabCollectionOwner,
        windowMutations: BrowserWindowShortcutMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.materializer = materializer
        self.containerRemoval = containerRemoval
        self.adopter = adopter
        self.structuralLookup = structuralLookup
        windowReconciler = RegularTabShortcutWindowReconciler(
            regularTabs: regularTabs,
            windowMutations: windowMutations
        )
    }

    /// Applies a presentation plan whose exact residences were revalidated by
    /// the aggregate transaction. No fallible work remains once model commit
    /// starts, so publication can safely follow the terminal runtime state.
    func applyAdmitted(
        to pin: ShortcutPin,
        transition: RegularTabShortcutWindowTransitionPlan,
        using authorization: AuthorizedDisplayedTabShortcutConversion,
        presentations: DisplayedShortcutPresentationResidencePlan
    ) {
        let tab = authorization.tab
        let plan = authorization.plan
        let sourceSpaceId = tab.spaceId

        var materializations: [(tab: Tab, window: BrowserWindowState)] = []
        var liveTabsByWindowId: [UUID: Tab] = [:]
        var changedWindows: [BrowserWindowState] = []

        containerRemoval.removeFromCurrentContainer(tab)
        let sourceBindingExecution = adopter.adopt(
            tab,
            for: pin,
            in: presentations.source.window.id,
            currentSpaceID: presentations.source.spaceID,
            presentationPage: presentations.source.page
        )
        liveTabsByWindowId[plan.firstWindowId] = tab

        for presentation in presentations.replicas {
            let windowState = presentation.window
            let liveTab = materializer.materialize(
                pin,
                in: windowState.id,
                currentSpaceId: presentation.spaceID,
                presentationPage: presentation.page
            )
            liveTabsByWindowId[windowState.id] = liveTab
            materializations.append((liveTab, windowState))
        }

        changedWindows = windowReconciler.reconcile(
            originalTabId: tab.id,
            splitTransition: transition,
            sourceSpaceId: sourceSpaceId,
            liveTabsByWindowId: liveTabsByWindowId,
            selectedWindowIds: Set(plan.selectedWindowIds),
            using: plan.runtime
        )

        structuralLookup.runAfterCurrentBatch {
            sourceBindingExecution.execute()
            for work in materializations {
                plan.runtime.webViewLifecycle
                    .materializeVisibleTabWebViewIfNeeded(
                        work.tab,
                        in: work.window
                    )
            }
            changedWindows.forEach(plan.runtime.persistWindowSession(for:))
        }
    }
}
