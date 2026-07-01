import Foundation

@MainActor
struct TabManagerRuntimeContext {
    private let currentProfileIdProvider: () -> UUID?
    private let defaultProfileIdProvider: () -> UUID?
    private let settingsProvider: () -> SumiSettingsService?
    private let profileExistsHandler: (UUID) -> Bool
    private let profileProvider: (UUID) -> Profile?
    private let windowStateProvider: (UUID) -> BrowserWindowState?
    private let windowsProvider: () -> [(UUID, BrowserWindowState)]
    private let windowStatesProvider: () -> [BrowserWindowState]
    private let updateTabVisibilityHandler: () -> Void
    private let materializeVisibleTabWebViewIfNeededHandler: (Tab, BrowserWindowState) -> Void
    private let loadTabHandler: (Tab) -> Void
    private let unloadTabHandler: (Tab) -> Void
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
        profileExists: @escaping (UUID) -> Bool = { _ in true },
        profile: @escaping (UUID) -> Profile? = { _ in nil },
        windowState: @escaping (UUID) -> BrowserWindowState? = { _ in nil },
        windows: @escaping () -> [(UUID, BrowserWindowState)] = { [] },
        windowStates: @escaping () -> [BrowserWindowState] = { [] },
        updateTabVisibility: @escaping () -> Void = {},
        materializeVisibleTabWebViewIfNeeded: @escaping (Tab, BrowserWindowState) -> Void = { _, _ in },
        loadTab: @escaping (Tab) -> Void = { _ in },
        unloadTab: @escaping (Tab) -> Void = { _ in },
        requireRemoveAllWebViews: @escaping (Tab, Bool) -> Void,
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
        self.profileExistsHandler = profileExists
        self.profileProvider = profile
        self.windowStateProvider = windowState
        self.windowsProvider = windows
        self.windowStatesProvider = windowStates
        self.updateTabVisibilityHandler = updateTabVisibility
        self.materializeVisibleTabWebViewIfNeededHandler = materializeVisibleTabWebViewIfNeeded
        self.loadTabHandler = loadTab
        self.unloadTabHandler = unloadTab
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
