import Foundation
import SumiDomain

/// Applies the non-fallible runtime half of an already authorized conversion.
/// The caller owns the structural transaction and exact split replacement.
@MainActor
final class DisplayedTabShortcutConversionCommitter {
    private struct WebViewMaterialization {
        let tab: Tab
        let windowState: BrowserWindowState
    }

    private let materializer: ShortcutTabMaterializer
    private let containerRemoval: ShortcutContainerRemovalOwner
    private let windowReconciler: RegularTabShortcutWindowReconciler
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        materializer: ShortcutTabMaterializer,
        containerRemoval: ShortcutContainerRemovalOwner,
        regularTabs: RegularTabCollectionOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.materializer = materializer
        self.containerRemoval = containerRemoval
        self.structuralLookup = structuralLookup
        windowReconciler = RegularTabShortcutWindowReconciler(
            regularTabs: regularTabs
        )
    }

    func apply(
        to pin: ShortcutPin,
        transition: RegularTabShortcutWindowTransitionPlan,
        using authorization: AuthorizedDisplayedTabShortcutConversion
    ) {
        let tab = authorization.tab
        let plan = authorization.plan
        let sourceSpaceId = tab.spaceId
        var materializations: [WebViewMaterialization] = []
        var liveTabsByWindowId: [UUID: Tab] = [:]
        var changedWindows: [BrowserWindowState] = []

        containerRemoval.removeFromCurrentContainer(tab)
        materializer.adopt(
            tab,
            for: pin,
            in: plan.firstWindowId,
            currentSpaceId: plan.firstWindow.currentSpaceId
        )
        liveTabsByWindowId[plan.firstWindowId] = tab

        for windowState in authorization.presentationWindows
            where windowState.id != plan.firstWindowId {
            let liveTab = materializer.materialize(
                pin,
                in: windowState.id,
                currentSpaceId: windowState.currentSpaceId
            )
            liveTabsByWindowId[windowState.id] = liveTab
            materializations.append(
                WebViewMaterialization(tab: liveTab, windowState: windowState)
            )
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
            for work in materializations {
                plan.runtime.webViewLifecycle
                    .materializeVisibleTabWebViewIfNeeded(
                        work.tab,
                        in: work.windowState
                    )
            }
            changedWindows.forEach(plan.runtime.persistWindowSession(for:))
        }
    }
}
