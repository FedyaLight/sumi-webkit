import Foundation

/// Restores one recently closed regular tab: resolves the destination space,
/// recreates the tab with its captured URL/title/back-forward presentation,
/// and selects the restored tab in the destination window.
@MainActor
final class ClosedTabRestoreService {
    private let regularLifecycle: TabRegularLifecycleOwner
    private let destinations: ClosedTabDestinationResolver
    private let publication: ClosedTabRestorePublication

    init(
        regularLifecycle: TabRegularLifecycleOwner,
        destinations: ClosedTabDestinationResolver,
        publication: ClosedTabRestorePublication
    ) {
        self.regularLifecycle = regularLifecycle
        self.destinations = destinations
        self.publication = publication
    }

    /// Returns `false` when no destination space can be resolved; the caller
    /// must then keep the recently-closed history item.
    func restore(_ tabState: RecentlyClosedTabState) -> Bool {
        restore(tabState, in: destinations.activeWindow)
    }

    func restore(
        _ tabState: RecentlyClosedTabState,
        in targetWindow: BrowserWindowState?
    ) -> Bool {
        guard let targetSpace = destinations.destinationSpace(
            sourceSpaceID: tabState.sourceSpaceId,
            sourceProfileID: tabState.profileId,
            fallbackWindow: targetWindow
        ) else {
            return false
        }

        let restoredURL = tabState.currentURL ?? tabState.url
        let restoredTab = regularLifecycle.createNewTab(
            url: restoredURL.absoluteString,
            in: targetSpace,
            activate: false
        )
        restoredTab.name = tabState.title
        restoredTab.loadURL(restoredURL)
        restoredTab.restoredCanGoBack = tabState.canGoBack
        restoredTab.restoredCanGoForward = tabState.canGoForward
        restoredTab.applyRestoredNavigationPresentation()

        publication.publish(restoredTab, in: targetWindow)
        return true
    }
}
