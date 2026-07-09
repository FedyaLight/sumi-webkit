import Foundation
import SumiBrowserCore

/// Typed runtime ports for TabManager side-effects (architecture plan W1).
/// Replaces the former mega-bag closure runtime context.
@MainActor
struct RuntimePortRegistry {
    var profileQuery: (any TabProfileQueryPort)?
    var windowQuery: (any TabWindowQueryPort)?
    var splitCoordination: (any TabSplitCoordinationPort)?
    var extensionLifecycle: (any TabExtensionLifecyclePort)?
    var sessionSideEffects: (any TabSessionSideEffectsPort)?
    var webViewLifecycle: TabManagerWebViewLifecycleService

    static let inactive = RuntimePortRegistry(
        profileQuery: nil,
        windowQuery: nil,
        splitCoordination: nil,
        extensionLifecycle: nil,
        sessionSideEffects: nil,
        webViewLifecycle: .inactive
    )

    init(
        profileQuery: (any TabProfileQueryPort)? = nil,
        windowQuery: (any TabWindowQueryPort)? = nil,
        splitCoordination: (any TabSplitCoordinationPort)? = nil,
        extensionLifecycle: (any TabExtensionLifecyclePort)? = nil,
        sessionSideEffects: (any TabSessionSideEffectsPort)? = nil,
        webViewLifecycle: TabManagerWebViewLifecycleService = .inactive
    ) {
        self.profileQuery = profileQuery
        self.windowQuery = windowQuery
        self.splitCoordination = splitCoordination
        self.extensionLifecycle = extensionLifecycle
        self.sessionSideEffects = sessionSideEffects
        self.webViewLifecycle = webViewLifecycle
    }

    mutating func attach(from browserManager: BrowserManager) {
        profileQuery = LiveTabProfileQueryPort(browserManager: browserManager)
        windowQuery = LiveTabWindowQueryPort(browserManager: browserManager)
        splitCoordination = LiveTabSplitCoordinationPort(browserManager: browserManager)
        extensionLifecycle = LiveTabExtensionLifecyclePort(browserManager: browserManager)
        sessionSideEffects = LiveTabSessionSideEffectsPort(browserManager: browserManager)
        webViewLifecycle = BrowserTabManagerWebViewLifecycleFactory.service(for: browserManager)
    }

    // MARK: - Profile query surface (former closure runtime context)

    var currentProfileId: UUID? { profileQuery?.currentProfileId }
    var defaultProfileId: UUID? { profileQuery?.defaultProfileId }
    var settings: SumiSettingsService? { profileQuery?.settings }

    func profileExists(_ profileId: UUID) -> Bool {
        profileQuery?.profileExists(profileId) ?? true
    }

    func profile(with profileId: UUID) -> Profile? {
        profileQuery?.profile(with: profileId)
    }

    // MARK: - Window query surface

    func windowState(for windowId: UUID) -> BrowserWindowState? {
        windowQuery?.windowState(for: windowId)
    }

    func forEachWindow(_ body: (UUID, BrowserWindowState) -> Void) {
        windowQuery?.forEachWindow(body)
    }

    func forEachWindowState(_ body: (BrowserWindowState) -> Void) {
        windowQuery?.forEachWindowState(body)
    }

    func updateTabVisibility() {
        windowQuery?.updateTabVisibility()
    }

    func validateWindowStates() {
        windowQuery?.validateWindowStates()
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        windowQuery?.persistWindowSession(for: windowState)
    }

    func syncWorkspaceThemeAcrossWindows(for space: Space, animate: Bool) {
        windowQuery?.syncWorkspaceThemeAcrossWindows(for: space, animate: animate)
    }

    // MARK: - Split coordination surface

    func handleTabClosure(_ tabId: UUID) {
        splitCoordination?.handleTabClosure(tabId)
    }

    func visibleSplitTabIds(for windowId: UUID) -> [UUID] {
        splitCoordination?.visibleSplitTabIds(for: windowId) ?? []
    }

    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        splitCoordination?.isTabVisibleInSplit(tabId, in: windowId) ?? false
    }

    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        splitCoordination?.isTabActiveInSplit(tabId, in: windowId) ?? false
    }

    func updateActiveSplitSide(for tabId: UUID, in windowId: UUID) {
        splitCoordination?.updateActiveSplitSide(for: tabId, in: windowId)
    }

    // MARK: - Extension lifecycle surface

    func notifyTabClosedIfLoaded(_ tab: Tab) {
        extensionLifecycle?.notifyTabClosedIfLoaded(tab)
    }

    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?) {
        extensionLifecycle?.notifyTabActivatedIfLoaded(newTab: newTab, previous: previous)
    }

    // MARK: - Session side-effects surface

    func captureClosedTab(_ tab: Tab, sourceSpaceId: UUID?) {
        sessionSideEffects?.captureClosedTab(tab, sourceSpaceId: sourceSpaceId)
    }

    func captureDeletedShortcutLauncher(_ pin: ShortcutPin) {
        sessionSideEffects?.captureDeletedShortcutLauncher(pin)
    }

    func notifications() -> (any BrowserNotificationPresenting)? {
        sessionSideEffects?.notifications()
    }

    func closeAuxiliaryMiniWindow(for tab: Tab, reason: AuxiliaryWindowCloseReason) {
        sessionSideEffects?.closeAuxiliaryMiniWindow(for: tab, reason: reason)
    }

    func isLiveFolder(_ folderId: UUID) -> Bool {
        sessionSideEffects?.isLiveFolder(folderId) ?? false
    }

    func deleteLiveFolderState(forFolderIds folderIds: Set<UUID>) {
        sessionSideEffects?.deleteLiveFolderState(forFolderIds: folderIds)
    }
}
