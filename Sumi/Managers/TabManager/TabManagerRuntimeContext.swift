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
    let webViewLifecycle: TabManagerWebViewLifecycleService
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
    private let persistWindowSessionHandler: (BrowserWindowState) -> Void
    private let syncWorkspaceThemeAcrossWindowsHandler: (Space, Bool) -> Void
    private let closeAuxiliaryMiniWindowHandler: (Tab, AuxiliaryWindowCloseReason) -> Void
    private let isLiveFolderProvider: (UUID) -> Bool
    private let deleteLiveFolderStateHandler: (Set<UUID>) -> Void

    init(
        currentProfileId: @escaping () -> UUID? = { nil },
        defaultProfileId: @escaping () -> UUID? = { nil },
        settings: @escaping () -> SumiSettingsService? = { nil },
        profileExists: @escaping (UUID) -> Bool = { _ in true },
        profile: @escaping (UUID) -> Profile? = { _ in nil },
        windowState: @escaping (UUID) -> BrowserWindowState? = { _ in nil },
        windows: @escaping () -> [(UUID, BrowserWindowState)] = { [] },
        windowStates: @escaping () -> [BrowserWindowState] = { [] },
        updateTabVisibility: @escaping () -> Void = { /* No-op. */ },
        webViewLifecycle: TabManagerWebViewLifecycleService = .inactive,
        handleTabClosure: @escaping (UUID) -> Void = { _ in /* No-op. */ },
        visibleSplitTabIds: @escaping (UUID) -> [UUID] = { _ in [] },
        isTabVisibleInSplit: @escaping (UUID, UUID) -> Bool = { _, _ in false },
        isTabActiveInSplit: @escaping (UUID, UUID) -> Bool = { _, _ in false },
        updateActiveSplitSide: @escaping (UUID, UUID) -> Void = { _, _ in /* No-op. */ },
        notifyTabClosedIfLoaded: @escaping (Tab) -> Void = { _ in /* No-op. */ },
        notifyTabActivatedIfLoaded: @escaping (Tab, Tab?) -> Void = { _, _ in /* No-op. */ },
        captureClosedTab: @escaping (Tab, UUID?) -> Void = { _, _ in /* No-op. */ },
        captureDeletedShortcutLauncher: @escaping (ShortcutPin) -> Void = { _ in /* No-op. */ },
        presentTabClosureToast: @escaping (Int) -> Void = { _ in /* No-op. */ },
        validateWindowStates: @escaping () -> Void = { /* No-op. */ },
        persistWindowSession: @escaping (BrowserWindowState) -> Void = { _ in /* No-op. */ },
        syncWorkspaceThemeAcrossWindows: @escaping (Space, Bool) -> Void = { _, _ in /* No-op. */ },
        closeAuxiliaryMiniWindow: @escaping (Tab, AuxiliaryWindowCloseReason) -> Void = { _, _ in /* No-op. */ },
        isLiveFolder: @escaping (UUID) -> Bool = { _ in false },
        deleteLiveFolderState: @escaping (Set<UUID>) -> Void = { _ in /* No-op. */ }
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
        self.webViewLifecycle = webViewLifecycle
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
        self.persistWindowSessionHandler = persistWindowSession
        self.syncWorkspaceThemeAcrossWindowsHandler = syncWorkspaceThemeAcrossWindows
        self.closeAuxiliaryMiniWindowHandler = closeAuxiliaryMiniWindow
        self.isLiveFolderProvider = isLiveFolder
        self.deleteLiveFolderStateHandler = deleteLiveFolderState
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

    func persistWindowSession(for windowState: BrowserWindowState) {
        persistWindowSessionHandler(windowState)
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
}
