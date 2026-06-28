import Foundation

@MainActor
protocol TabManagerRuntimeContext: AnyObject {
    var currentProfileId: UUID? { get }
    var defaultProfileId: UUID? { get }
    var settings: SumiSettingsService? { get }
    var activeWindowId: UUID? { get }
    var activeWindowState: BrowserWindowState? { get }

    func profileExists(_ profileId: UUID) -> Bool
    func profile(with profileId: UUID) -> Profile?
    func windowState(for windowId: UUID) -> BrowserWindowState?
    func forEachWindow(_ body: (UUID, BrowserWindowState) -> Void)
    func forEachWindowState(_ body: (BrowserWindowState) -> Void)

    func updateTabVisibility()
    func materializeVisibleTabWebViewIfNeeded(_ tab: Tab, in windowState: BrowserWindowState)
    func loadTab(_ tab: Tab)
    func unloadTab(_ tab: Tab)
    func removeAllWebViews(for tab: Tab, closeActiveFullscreenMedia: Bool)
    func requireRemoveAllWebViews(for tab: Tab, closeActiveFullscreenMedia: Bool)
    func windowIDsTrackingWebViews(for tabId: UUID) -> [UUID]
    @available(macOS 15.5, *)
    func rebuildLiveWebViews(for tab: Tab, preferredPrimaryWindowId: UUID?, load url: URL?)

    func handleTabClosure(_ tabId: UUID)
    func visibleSplitTabIds(for windowId: UUID) -> [UUID]
    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool
    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool
    func updateActiveSplitSide(for tabId: UUID, in windowId: UUID)

    func notifyTabClosedIfLoaded(_ tab: Tab)
    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?)
    func captureClosedTab(_ tab: Tab, sourceSpaceId: UUID?)
    func captureDeletedShortcutLauncher(_ pin: ShortcutPin)
    func presentTabClosureToast(tabCount: Int)

    func validateWindowStates()
    func syncWorkspaceThemeAcrossWindows(for space: Space, animate: Bool)
    func closeAuxiliaryMiniWindow(for tab: Tab, reason: AuxiliaryWindowCloseReason)

    func isLiveFolder(_ folderId: UUID) -> Bool
    func deleteLiveFolderState(forFolderIds folderIds: Set<UUID>)
}

@MainActor
final class BrowserManagerTabRuntimeContext: TabManagerRuntimeContext {
    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    var currentProfileId: UUID? {
        browserManager?.currentProfile?.id
    }

    var defaultProfileId: UUID? {
        currentProfileId ?? browserManager?.profileManager.profiles.first?.id
    }

    var settings: SumiSettingsService? {
        browserManager?.sumiSettings
    }

    var activeWindowId: UUID? {
        browserManager?.windowRegistry?.activeWindow?.id
    }

    var activeWindowState: BrowserWindowState? {
        browserManager?.windowRegistry?.activeWindow
    }

    func profileExists(_ profileId: UUID) -> Bool {
        guard let browserManager else { return true }
        return browserManager.profileManager.profiles.contains { $0.id == profileId }
    }

    func profile(with profileId: UUID) -> Profile? {
        browserManager?.profileManager.profiles.first { $0.id == profileId }
    }

    func windowState(for windowId: UUID) -> BrowserWindowState? {
        browserManager?.windowRegistry?.windows[windowId]
    }

    func forEachWindow(_ body: (UUID, BrowserWindowState) -> Void) {
        for (windowId, windowState) in browserManager?.windowRegistry?.windows ?? [:] {
            body(windowId, windowState)
        }
    }

    func forEachWindowState(_ body: (BrowserWindowState) -> Void) {
        for windowState in browserManager?.windowRegistry?.allWindows ?? [] {
            body(windowState)
        }
    }

    func updateTabVisibility() {
        browserManager?.compositorManager.updateTabVisibility()
    }

    func materializeVisibleTabWebViewIfNeeded(_ tab: Tab, in windowState: BrowserWindowState) {
        browserManager?.materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
    }

    func loadTab(_ tab: Tab) {
        browserManager?.compositorManager.loadTab(tab)
    }

    func unloadTab(_ tab: Tab) {
        browserManager?.compositorManager.unloadTab(tab)
    }

    func removeAllWebViews(for tab: Tab, closeActiveFullscreenMedia: Bool) {
        browserManager?.webViewCoordinator?.removeAllWebViews(
            for: tab,
            closeActiveFullscreenMedia: closeActiveFullscreenMedia
        )
    }

    func requireRemoveAllWebViews(for tab: Tab, closeActiveFullscreenMedia: Bool) {
        guard let browserManager else { return }
        browserManager.requireWebViewCoordinator().removeAllWebViews(
            for: tab,
            closeActiveFullscreenMedia: closeActiveFullscreenMedia
        )
    }

    func windowIDsTrackingWebViews(for tabId: UUID) -> [UUID] {
        browserManager?.webViewCoordinator?.windowIDs(for: tabId) ?? []
    }

    @available(macOS 15.5, *)
    func rebuildLiveWebViews(for tab: Tab, preferredPrimaryWindowId: UUID?, load url: URL?) {
        browserManager?.webViewCoordinator?.rebuildLiveWebViews(
            for: tab,
            preferredPrimaryWindowId: preferredPrimaryWindowId,
            load: url
        )
    }

    func handleTabClosure(_ tabId: UUID) {
        browserManager?.splitManager.handleTabClosure(tabId)
    }

    func visibleSplitTabIds(for windowId: UUID) -> [UUID] {
        browserManager?.splitManager.visibleTabIds(for: windowId) ?? []
    }

    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        browserManager?.splitManager.isTabVisibleInSplit(tabId, in: windowId) == true
    }

    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        browserManager?.splitManager.isTabActiveInSplit(tabId, in: windowId) == true
    }

    func updateActiveSplitSide(for tabId: UUID, in windowId: UUID) {
        browserManager?.splitManager.updateActiveSide(for: tabId, in: windowId)
    }

    func notifyTabClosedIfLoaded(_ tab: Tab) {
        browserManager?.extensionsModule.notifyTabClosedIfLoaded(tab)
    }

    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?) {
        browserManager?.extensionsModule.notifyTabActivatedIfLoaded(
            newTab: newTab,
            previous: previous
        )
    }

    func captureClosedTab(_ tab: Tab, sourceSpaceId: UUID?) {
        browserManager?.recentlyClosedManager.captureClosedTab(
            tab,
            sourceSpaceId: sourceSpaceId,
            currentURL: tab.url,
            canGoBack: tab.canGoBack,
            canGoForward: tab.canGoForward
        )
    }

    func captureDeletedShortcutLauncher(_ pin: ShortcutPin) {
        browserManager?.recentlyClosedManager.captureDeletedShortcutLauncher(pin)
    }

    func presentTabClosureToast(tabCount: Int) {
        browserManager?.presentTabClosureToast(tabCount: tabCount)
    }

    func validateWindowStates() {
        browserManager?.validateWindowStates()
    }

    func syncWorkspaceThemeAcrossWindows(for space: Space, animate: Bool) {
        browserManager?.syncWorkspaceThemeAcrossWindows(for: space, animate: animate)
    }

    func closeAuxiliaryMiniWindow(for tab: Tab, reason: AuxiliaryWindowCloseReason) {
        browserManager?.closeAuxiliaryMiniWindow(for: tab, reason: reason)
    }

    func isLiveFolder(_ folderId: UUID) -> Bool {
        browserManager?.liveFolderManager.isLiveFolder(folderId) == true
    }

    func deleteLiveFolderState(forFolderIds folderIds: Set<UUID>) {
        browserManager?.liveFolderManager.deleteState(forFolderIds: folderIds)
    }
}
