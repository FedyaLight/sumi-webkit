import Foundation

/// Executes a previously authorized displayed-tab conversion as one
/// structural batch. It performs no planning or stale-plan recovery.
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

    func commit(
        to pin: ShortcutPin,
        using authorization: AuthorizedDisplayedTabShortcutConversion
    ) {
        let tab = authorization.tab
        let plan = authorization.plan
        let sourceSpaceId = tab.spaceId
        var materializations: [WebViewMaterialization] = []
        var liveTabsByWindowId: [UUID: Tab] = [:]
        var changedWindows: [BrowserWindowState] = []

        structuralLookup.withTransaction {
            authorization.structure.commit(insertedPin: pin)
            containerRemoval.removeFromCurrentContainer(tab)
            materializer.adopt(
                tab,
                for: pin,
                in: plan.firstWindowId,
                currentSpaceId: plan.firstWindow.currentSpaceId
            )
            liveTabsByWindowId[plan.firstWindowId] = tab

            for windowState in authorization.selectedWindows
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
                sourceSpaceId: sourceSpaceId,
                liveTabsByWindowId: liveTabsByWindowId,
                selectedWindowIds: Set(plan.selectedWindowIds),
                using: plan.runtime
            )
        }

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
