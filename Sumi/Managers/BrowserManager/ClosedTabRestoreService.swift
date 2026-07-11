import Foundation

/// Restores one recently closed regular tab: resolves the destination space,
/// recreates the tab with its captured URL/title/back-forward presentation,
/// and selects the restored tab in the destination window.
@MainActor
final class ClosedTabRestoreService {
    private let tabManager: @MainActor () -> TabManager?
    private let activeWindow: @MainActor () -> BrowserWindowState?
    private let selectRestoredTab: @MainActor (Tab, BrowserWindowState) -> Void

    init(
        tabManager: @escaping @MainActor () -> TabManager?,
        activeWindow: @escaping @MainActor () -> BrowserWindowState?,
        selectRestoredTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void
    ) {
        self.tabManager = tabManager
        self.activeWindow = activeWindow
        self.selectRestoredTab = selectRestoredTab
    }

    /// Returns `false` when no destination space can be resolved; the caller
    /// must then keep the recently-closed history item.
    func restore(_ tabState: RecentlyClosedTabState) -> Bool {
        guard let tabManager = tabManager() else { return false }
        let targetWindow = activeWindow()
        guard let targetSpace = destinationSpace(
            sourceSpaceId: tabState.sourceSpaceId,
            sourceProfileId: tabState.profileId,
            fallbackWindow: targetWindow,
            tabManager: tabManager
        ) else {
            return false
        }

        let restoredURL = tabState.currentURL ?? tabState.url
        let restoredTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: restoredURL.absoluteString,
            in: targetSpace,
            activate: false
        )
        restoredTab.name = tabState.title
        restoredTab.loadURL(restoredURL)
        restoredTab.restoredCanGoBack = tabState.canGoBack
        restoredTab.restoredCanGoForward = tabState.canGoForward
        restoredTab.applyRestoredNavigationPresentation()

        if let targetWindow {
            selectRestoredTab(restoredTab, targetWindow)
        } else {
            tabManager.activeSelectionOwner.setActiveTab(restoredTab)
        }
        return true
    }

    private func destinationSpace(
        sourceSpaceId: UUID?,
        sourceProfileId: UUID?,
        fallbackWindow: BrowserWindowState?,
        tabManager: TabManager
    ) -> Space? {
        if let sourceSpaceId,
           let sourceSpace = tabManager.spaceStateOwner.space(with: sourceSpaceId) {
            return sourceSpace
        }
        if let spaceId = fallbackWindow?.currentSpaceId,
           let windowSpace = tabManager.spaceStateOwner.space(with: spaceId) {
            return windowSpace
        }
        if let sourceProfileId,
           let profileSpace = firstSpace(for: sourceProfileId, tabManager: tabManager) {
            return profileSpace
        }
        if let profileId = fallbackWindow?.currentProfileId,
           let profileSpace = firstSpace(for: profileId, tabManager: tabManager) {
            return profileSpace
        }
        return nil
    }

    private func firstSpace(
        for profileId: UUID,
        tabManager: TabManager
    ) -> Space? {
        tabManager.spaceStateOwner.spaces.first(where: { $0.profileId == profileId })
    }
}
