import Foundation

/// Typed runtime ports for TabManager side-effects (architecture plan W1).
/// Replaces the former mega-bag closure runtime context.
@MainActor
struct RuntimePortRegistry {
    let profileQuery: any TabProfileQueryPort
    let windowQuery: any TabWindowQueryPort
    let splitCoordination: any TabSplitCoordinationPort
    let extensionLifecycle: any TabExtensionLifecyclePort
    let sessionSideEffects: any TabSessionSideEffectsPort
    let webViewLifecycle: TabManagerWebViewLifecycleService

    init(
        profileQuery: any TabProfileQueryPort,
        windowQuery: any TabWindowQueryPort,
        splitCoordination: any TabSplitCoordinationPort,
        extensionLifecycle: any TabExtensionLifecyclePort,
        sessionSideEffects: any TabSessionSideEffectsPort,
        webViewLifecycle: TabManagerWebViewLifecycleService
    ) {
        self.profileQuery = profileQuery
        self.windowQuery = windowQuery
        self.splitCoordination = splitCoordination
        self.extensionLifecycle = extensionLifecycle
        self.sessionSideEffects = sessionSideEffects
        self.webViewLifecycle = webViewLifecycle
    }

    // MARK: - Profile query surface (former closure runtime context)

    var currentProfileId: UUID? { profileQuery.currentProfileId }
    var defaultProfileId: UUID? { profileQuery.defaultProfileId }
    var settings: SumiSettingsService? { profileQuery.settings }

    func profileExists(_ profileId: UUID) -> Bool {
        profileQuery.profileExists(profileId)
    }

    func profile(with profileId: UUID) -> Profile? {
        profileQuery.profile(with: profileId)
    }

    // MARK: - Window query surface

    func windowState(for windowId: UUID) -> BrowserWindowState? {
        windowQuery.windowState(for: windowId)
    }

    func forEachWindow(_ body: (UUID, BrowserWindowState) -> Void) {
        windowQuery.forEachWindow(body)
    }

    func forEachWindowState(_ body: (BrowserWindowState) -> Void) {
        windowQuery.forEachWindowState(body)
    }

    func updateTabVisibility() {
        windowQuery.updateTabVisibility()
    }

    func validateWindowStates() -> Set<UUID> {
        windowQuery.validateWindowStates()
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        windowQuery.persistWindowSession(for: windowState)
    }

    func syncWorkspaceThemeAcrossWindows(for space: Space, animate: Bool) {
        windowQuery.syncWorkspaceThemeAcrossWindows(for: space, animate: animate)
    }

    // MARK: - Split coordination surface

    func handleTabClosure(_ tabId: UUID) {
        splitCoordination.handleTabClosure(tabId)
    }

    func stageTabClosures(
        _ tabIds: Set<UUID>
    ) -> (any TabSplitClosureSettlement)? {
        splitCoordination.stageTabClosures(tabIds)
    }

    func visibleSplitTabIds(for windowId: UUID) -> [UUID] {
        splitCoordination.visibleSplitTabIds(for: windowId)
    }

    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        splitCoordination.isTabVisibleInSplit(tabId, in: windowId)
    }

    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        splitCoordination.isTabActiveInSplit(tabId, in: windowId)
    }

    // MARK: - Extension lifecycle surface

    func notifyTabClosedIfLoaded(_ tab: Tab) {
        extensionLifecycle.notifyTabClosedIfLoaded(tab)
    }

    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?) {
        extensionLifecycle.notifyTabActivatedIfLoaded(newTab: newTab, previous: previous)
    }

    // MARK: - Session side-effects surface

    func captureClosedTab(_ tab: Tab, sourceSpaceId: UUID?) {
        sessionSideEffects.captureClosedTab(tab, sourceSpaceId: sourceSpaceId)
    }

    func captureDeletedShortcutLauncher(_ pin: ShortcutPin) {
        sessionSideEffects.captureDeletedShortcutLauncher(pin)
    }

    func notifications() -> (any BrowserNotificationPresenting)? {
        sessionSideEffects.notifications()
    }

    func closeAuxiliaryMiniWindow(for tab: Tab, reason: AuxiliaryWindowCloseReason) {
        sessionSideEffects.closeAuxiliaryMiniWindow(for: tab, reason: reason)
    }

    func isLiveFolder(_ folderId: UUID) -> Bool {
        sessionSideEffects.isLiveFolder(folderId)
    }

    func deleteLiveFolderState(forFolderIds folderIds: Set<UUID>) {
        sessionSideEffects.deleteLiveFolderState(forFolderIds: folderIds)
    }
}
