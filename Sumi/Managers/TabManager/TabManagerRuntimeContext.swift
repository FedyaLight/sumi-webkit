import Foundation

@MainActor
struct TabManagerRuntimeContext {
    private let currentProfileIdProvider: () -> UUID?
    private let defaultProfileIdProvider: () -> UUID?
    private let settingsProvider: () -> SumiSettingsService?
    private let activeWindowIdProvider: () -> UUID?
    private let activeWindowStateProvider: () -> BrowserWindowState?
    private let profileExistsHandler: (UUID) -> Bool
    private let profileProvider: (UUID) -> Profile?
    private let windowStateProvider: (UUID) -> BrowserWindowState?
    private let windowsProvider: () -> [(UUID, BrowserWindowState)]
    private let windowStatesProvider: () -> [BrowserWindowState]
    private let updateTabVisibilityHandler: () -> Void
    private let materializeVisibleTabWebViewIfNeededHandler: (Tab, BrowserWindowState) -> Void
    private let loadTabHandler: (Tab) -> Void
    private let unloadTabHandler: (Tab) -> Void
    private let removeAllWebViewsHandler: (Tab, Bool) -> Void
    private let requireRemoveAllWebViewsHandler: (Tab, Bool) -> Void
    private let windowIDsTrackingWebViewsProvider: (UUID) -> [UUID]
    private let rebuildLiveWebViewsHandler: (Tab, UUID?, URL?) -> Void
    private let handleTabClosureHandler: (UUID) -> Void
    private let visibleSplitTabIdsProvider: (UUID) -> [UUID]
    private let isTabVisibleInSplitProvider: (UUID, UUID) -> Bool
    private let isTabActiveInSplitProvider: (UUID, UUID) -> Bool
    private let updateActiveSplitSideHandler: (UUID, UUID) -> Void
    private let notifyTabClosedIfLoadedHandler: (Tab) -> Void
    private let notifyTabActivatedIfLoadedHandler: (Tab, Tab?) -> Void
    private let captureClosedTabHandler: (Tab, UUID?) -> Void
    private let captureDeletedShortcutLauncherHandler: (ShortcutPin) -> Void
    private let presentTabClosureToastHandler: (Int) -> Void
    private let validateWindowStatesHandler: () -> Void
    private let syncWorkspaceThemeAcrossWindowsHandler: (Space, Bool) -> Void
    private let closeAuxiliaryMiniWindowHandler: (Tab, AuxiliaryWindowCloseReason) -> Void
    private let isLiveFolderProvider: (UUID) -> Bool
    private let deleteLiveFolderStateHandler: (Set<UUID>) -> Void
    private let prepareTabHandler: (Tab) -> Void

    init(
        currentProfileId: @escaping () -> UUID? = { nil },
        defaultProfileId: @escaping () -> UUID? = { nil },
        settings: @escaping () -> SumiSettingsService? = { nil },
        activeWindowId: @escaping () -> UUID? = { nil },
        activeWindowState: @escaping () -> BrowserWindowState? = { nil },
        profileExists: @escaping (UUID) -> Bool = { _ in true },
        profile: @escaping (UUID) -> Profile? = { _ in nil },
        windowState: @escaping (UUID) -> BrowserWindowState? = { _ in nil },
        windows: @escaping () -> [(UUID, BrowserWindowState)] = { [] },
        windowStates: @escaping () -> [BrowserWindowState] = { [] },
        updateTabVisibility: @escaping () -> Void = {},
        materializeVisibleTabWebViewIfNeeded: @escaping (Tab, BrowserWindowState) -> Void = { _, _ in },
        loadTab: @escaping (Tab) -> Void = { _ in },
        unloadTab: @escaping (Tab) -> Void = { _ in },
        removeAllWebViews: @escaping (Tab, Bool) -> Void = { _, _ in },
        requireRemoveAllWebViews: @escaping (Tab, Bool) -> Void = { _, _ in },
        windowIDsTrackingWebViews: @escaping (UUID) -> [UUID] = { _ in [] },
        rebuildLiveWebViews: @escaping (Tab, UUID?, URL?) -> Void = { _, _, _ in },
        handleTabClosure: @escaping (UUID) -> Void = { _ in },
        visibleSplitTabIds: @escaping (UUID) -> [UUID] = { _ in [] },
        isTabVisibleInSplit: @escaping (UUID, UUID) -> Bool = { _, _ in false },
        isTabActiveInSplit: @escaping (UUID, UUID) -> Bool = { _, _ in false },
        updateActiveSplitSide: @escaping (UUID, UUID) -> Void = { _, _ in },
        notifyTabClosedIfLoaded: @escaping (Tab) -> Void = { _ in },
        notifyTabActivatedIfLoaded: @escaping (Tab, Tab?) -> Void = { _, _ in },
        captureClosedTab: @escaping (Tab, UUID?) -> Void = { _, _ in },
        captureDeletedShortcutLauncher: @escaping (ShortcutPin) -> Void = { _ in },
        presentTabClosureToast: @escaping (Int) -> Void = { _ in },
        validateWindowStates: @escaping () -> Void = {},
        syncWorkspaceThemeAcrossWindows: @escaping (Space, Bool) -> Void = { _, _ in },
        closeAuxiliaryMiniWindow: @escaping (Tab, AuxiliaryWindowCloseReason) -> Void = { _, _ in },
        isLiveFolder: @escaping (UUID) -> Bool = { _ in false },
        deleteLiveFolderState: @escaping (Set<UUID>) -> Void = { _ in },
        prepareTab: @escaping (Tab) -> Void = { _ in }
    ) {
        self.currentProfileIdProvider = currentProfileId
        self.defaultProfileIdProvider = defaultProfileId
        self.settingsProvider = settings
        self.activeWindowIdProvider = activeWindowId
        self.activeWindowStateProvider = activeWindowState
        self.profileExistsHandler = profileExists
        self.profileProvider = profile
        self.windowStateProvider = windowState
        self.windowsProvider = windows
        self.windowStatesProvider = windowStates
        self.updateTabVisibilityHandler = updateTabVisibility
        self.materializeVisibleTabWebViewIfNeededHandler = materializeVisibleTabWebViewIfNeeded
        self.loadTabHandler = loadTab
        self.unloadTabHandler = unloadTab
        self.removeAllWebViewsHandler = removeAllWebViews
        self.requireRemoveAllWebViewsHandler = requireRemoveAllWebViews
        self.windowIDsTrackingWebViewsProvider = windowIDsTrackingWebViews
        self.rebuildLiveWebViewsHandler = rebuildLiveWebViews
        self.handleTabClosureHandler = handleTabClosure
        self.visibleSplitTabIdsProvider = visibleSplitTabIds
        self.isTabVisibleInSplitProvider = isTabVisibleInSplit
        self.isTabActiveInSplitProvider = isTabActiveInSplit
        self.updateActiveSplitSideHandler = updateActiveSplitSide
        self.notifyTabClosedIfLoadedHandler = notifyTabClosedIfLoaded
        self.notifyTabActivatedIfLoadedHandler = notifyTabActivatedIfLoaded
        self.captureClosedTabHandler = captureClosedTab
        self.captureDeletedShortcutLauncherHandler = captureDeletedShortcutLauncher
        self.presentTabClosureToastHandler = presentTabClosureToast
        self.validateWindowStatesHandler = validateWindowStates
        self.syncWorkspaceThemeAcrossWindowsHandler = syncWorkspaceThemeAcrossWindows
        self.closeAuxiliaryMiniWindowHandler = closeAuxiliaryMiniWindow
        self.isLiveFolderProvider = isLiveFolder
        self.deleteLiveFolderStateHandler = deleteLiveFolderState
        self.prepareTabHandler = prepareTab
    }

    var currentProfileId: UUID? { currentProfileIdProvider() }
    var defaultProfileId: UUID? { defaultProfileIdProvider() }
    var settings: SumiSettingsService? { settingsProvider() }
    var activeWindowId: UUID? { activeWindowIdProvider() }
    var activeWindowState: BrowserWindowState? { activeWindowStateProvider() }

    func profileExists(_ profileId: UUID) -> Bool {
        profileExistsHandler(profileId)
    }

    func profile(with profileId: UUID) -> Profile? {
        profileProvider(profileId)
    }

    func windowState(for windowId: UUID) -> BrowserWindowState? {
        windowStateProvider(windowId)
    }

    func forEachWindow(_ body: (UUID, BrowserWindowState) -> Void) {
        for (windowId, windowState) in windowsProvider() {
            body(windowId, windowState)
        }
    }

    func forEachWindowState(_ body: (BrowserWindowState) -> Void) {
        for windowState in windowStatesProvider() {
            body(windowState)
        }
    }

    func updateTabVisibility() {
        updateTabVisibilityHandler()
    }

    func materializeVisibleTabWebViewIfNeeded(_ tab: Tab, in windowState: BrowserWindowState) {
        materializeVisibleTabWebViewIfNeededHandler(tab, windowState)
    }

    func loadTab(_ tab: Tab) {
        loadTabHandler(tab)
    }

    func unloadTab(_ tab: Tab) {
        unloadTabHandler(tab)
    }

    func removeAllWebViews(for tab: Tab, closeActiveFullscreenMedia: Bool) {
        removeAllWebViewsHandler(tab, closeActiveFullscreenMedia)
    }

    func requireRemoveAllWebViews(for tab: Tab, closeActiveFullscreenMedia: Bool) {
        requireRemoveAllWebViewsHandler(tab, closeActiveFullscreenMedia)
    }

    func windowIDsTrackingWebViews(for tabId: UUID) -> [UUID] {
        windowIDsTrackingWebViewsProvider(tabId)
    }

    @available(macOS 15.5, *)
    func rebuildLiveWebViews(for tab: Tab, preferredPrimaryWindowId: UUID?, load url: URL?) {
        rebuildLiveWebViewsHandler(tab, preferredPrimaryWindowId, url)
    }

    func handleTabClosure(_ tabId: UUID) {
        handleTabClosureHandler(tabId)
    }

    func visibleSplitTabIds(for windowId: UUID) -> [UUID] {
        visibleSplitTabIdsProvider(windowId)
    }

    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        isTabVisibleInSplitProvider(tabId, windowId)
    }

    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        isTabActiveInSplitProvider(tabId, windowId)
    }

    func updateActiveSplitSide(for tabId: UUID, in windowId: UUID) {
        updateActiveSplitSideHandler(tabId, windowId)
    }

    func notifyTabClosedIfLoaded(_ tab: Tab) {
        notifyTabClosedIfLoadedHandler(tab)
    }

    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?) {
        notifyTabActivatedIfLoadedHandler(newTab, previous)
    }

    func captureClosedTab(_ tab: Tab, sourceSpaceId: UUID?) {
        captureClosedTabHandler(tab, sourceSpaceId)
    }

    func captureDeletedShortcutLauncher(_ pin: ShortcutPin) {
        captureDeletedShortcutLauncherHandler(pin)
    }

    func presentTabClosureToast(tabCount: Int) {
        presentTabClosureToastHandler(tabCount)
    }

    func validateWindowStates() {
        validateWindowStatesHandler()
    }

    func syncWorkspaceThemeAcrossWindows(for space: Space, animate: Bool) {
        syncWorkspaceThemeAcrossWindowsHandler(space, animate)
    }

    func closeAuxiliaryMiniWindow(for tab: Tab, reason: AuxiliaryWindowCloseReason) {
        closeAuxiliaryMiniWindowHandler(tab, reason)
    }

    func isLiveFolder(_ folderId: UUID) -> Bool {
        isLiveFolderProvider(folderId)
    }

    func deleteLiveFolderState(forFolderIds folderIds: Set<UUID>) {
        deleteLiveFolderStateHandler(folderIds)
    }

    func prepareTab(_ tab: Tab) {
        prepareTabHandler(tab)
    }
}

extension TabManagerRuntimeContext {
    static func live(browserManager: BrowserManager) -> TabManagerRuntimeContext {
        TabManagerRuntimeContext(
            currentProfileId: { [weak browserManager] in
                browserManager?.currentProfile?.id
            },
            defaultProfileId: { [weak browserManager] in
                browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            },
            activeWindowId: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow?.id
            },
            activeWindowState: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            profileExists: { [weak browserManager] profileId in
                guard let browserManager else { return true }
                return browserManager.profileManager.profiles.contains { $0.id == profileId }
            },
            profile: { [weak browserManager] profileId in
                browserManager?.profileManager.profiles.first { $0.id == profileId }
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            windows: { [weak browserManager] in
                browserManager?.windowRegistry?.windows.map { ($0.key, $0.value) } ?? []
            },
            windowStates: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            updateTabVisibility: { [weak browserManager] in
                browserManager?.compositorManager.updateTabVisibility()
            },
            materializeVisibleTabWebViewIfNeeded: { [weak browserManager] tab, windowState in
                browserManager?.materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
            },
            loadTab: { [weak browserManager] tab in
                browserManager?.compositorManager.loadTab(tab)
            },
            unloadTab: { [weak browserManager] tab in
                browserManager?.compositorManager.unloadTab(tab)
            },
            removeAllWebViews: { [weak browserManager] tab, closeActiveFullscreenMedia in
                browserManager?.webViewCoordinator?.removeAllWebViews(
                    for: tab,
                    closeActiveFullscreenMedia: closeActiveFullscreenMedia
                )
            },
            requireRemoveAllWebViews: { [weak browserManager] tab, closeActiveFullscreenMedia in
                guard let browserManager else { return }
                browserManager.requireWebViewCoordinator().removeAllWebViews(
                    for: tab,
                    closeActiveFullscreenMedia: closeActiveFullscreenMedia
                )
            },
            windowIDsTrackingWebViews: { [weak browserManager] tabId in
                browserManager?.webViewCoordinator?.windowIDs(for: tabId) ?? []
            },
            rebuildLiveWebViews: { [weak browserManager] tab, preferredPrimaryWindowId, url in
                if #available(macOS 15.5, *) {
                    browserManager?.webViewCoordinator?.rebuildLiveWebViews(
                        for: tab,
                        preferredPrimaryWindowId: preferredPrimaryWindowId,
                        load: url
                    )
                }
            },
            handleTabClosure: { [weak browserManager] tabId in
                browserManager?.splitManager.handleTabClosure(tabId)
            },
            visibleSplitTabIds: { [weak browserManager] windowId in
                browserManager?.splitManager.visibleTabIds(for: windowId) ?? []
            },
            isTabVisibleInSplit: { [weak browserManager] tabId, windowId in
                browserManager?.splitManager.isTabVisibleInSplit(tabId, in: windowId) == true
            },
            isTabActiveInSplit: { [weak browserManager] tabId, windowId in
                browserManager?.splitManager.isTabActiveInSplit(tabId, in: windowId) == true
            },
            updateActiveSplitSide: { [weak browserManager] tabId, windowId in
                browserManager?.splitManager.updateActiveSide(for: tabId, in: windowId)
            },
            notifyTabClosedIfLoaded: { [weak browserManager] tab in
                browserManager?.extensionsModule.notifyTabClosedIfLoaded(tab)
            },
            notifyTabActivatedIfLoaded: { [weak browserManager] newTab, previous in
                browserManager?.extensionsModule.notifyTabActivatedIfLoaded(
                    newTab: newTab,
                    previous: previous
                )
            },
            captureClosedTab: { [weak browserManager] tab, sourceSpaceId in
                browserManager?.recentlyClosedManager.captureClosedTab(
                    tab,
                    sourceSpaceId: sourceSpaceId,
                    currentURL: tab.url,
                    canGoBack: tab.canGoBack,
                    canGoForward: tab.canGoForward
                )
            },
            captureDeletedShortcutLauncher: { [weak browserManager] pin in
                browserManager?.recentlyClosedManager.captureDeletedShortcutLauncher(pin)
            },
            presentTabClosureToast: { [weak browserManager] tabCount in
                browserManager?.presentTabClosureToast(tabCount: tabCount)
            },
            validateWindowStates: { [weak browserManager] in
                browserManager?.validateWindowStates()
            },
            syncWorkspaceThemeAcrossWindows: { [weak browserManager] space, animate in
                browserManager?.syncWorkspaceThemeAcrossWindows(for: space, animate: animate)
            },
            closeAuxiliaryMiniWindow: { [weak browserManager] tab, reason in
                browserManager?.closeAuxiliaryMiniWindow(for: tab, reason: reason)
            },
            isLiveFolder: { [weak browserManager] folderId in
                browserManager?.liveFolderManager.isLiveFolder(folderId) == true
            },
            deleteLiveFolderState: { [weak browserManager] folderIds in
                browserManager?.liveFolderManager.deleteState(forFolderIds: folderIds)
            },
            prepareTab: { [weak browserManager] tab in
                guard let browserManager else { return }
                tab.attachBrowserRuntime(browserManager.makeTabBrowserRuntime())
            }
        )
    }
}
