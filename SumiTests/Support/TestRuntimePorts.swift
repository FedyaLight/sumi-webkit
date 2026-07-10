import Foundation
import SumiWebRuntime

@testable import Sumi

/// Builds a `RuntimePortRegistry` from closures for unit tests that previously
/// constructed the legacy closure-bag runtime context with provider/handler bags.
@MainActor
enum TestRuntimePorts {
    static func webViewLifecycle(
        materializeVisibleTabWebViewIfNeeded: @escaping (Tab, BrowserWindowState) -> Void = { _, _ in },
        loadTab: @escaping (Tab) -> Void = { _ in },
        unloadTab: @escaping (Tab) -> Void = { _ in },
        requireRemoveAllWebViews: @escaping (Tab, Bool) -> Void = { _, _ in },
        windowIDsTrackingWebViews: @escaping (UUID) -> [UUID] = { _ in [] },
        primaryTrackedWindowId: @escaping (UUID) -> UUID? = { _ in nil },
        rebuildLiveWebViews: @escaping (Tab, UUID?, URL?) -> Void = { _, _, _ in },
        prepareTab: @escaping (Tab) -> Void = { _ in },
        anyLiveWebView: @escaping (Tab) -> WKWebView? = { _ in nil },
        hasUntrackedOwnedWebView: @escaping (Tab) -> Bool = { _ in false },
        executeProfileAssignment: @escaping (
            Tab,
            Profile,
            DeferredWebViewProfileAssignmentIntent
        ) -> TabProfileAssignmentExecutionOutcome = { tab, _, intent in
            tab.commitProfileAssignmentIntent(intent) ? .committed : .stale
        }
    ) -> TabManagerWebViewLifecycleService {
        TabManagerWebViewLifecycleService(
            materializeVisibleTabWebViewIfNeeded: materializeVisibleTabWebViewIfNeeded,
            loadTab: loadTab,
            unloadTab: unloadTab,
            requireRemoveAllWebViews: requireRemoveAllWebViews,
            windowIDsTrackingWebViews: windowIDsTrackingWebViews,
            primaryTrackedWindowId: primaryTrackedWindowId,
            rebuildLiveWebViews: rebuildLiveWebViews,
            prepareTab: prepareTab,
            anyLiveWebView: anyLiveWebView,
            hasUntrackedOwnedWebView: hasUntrackedOwnedWebView,
            executeProfileAssignment: executeProfileAssignment
        )
    }

    static func make(
        currentProfileId: @escaping () -> UUID? = { nil },
        defaultProfileId: @escaping () -> UUID? = { nil },
        settings: @escaping () -> SumiSettingsService? = { nil },
        profileExists: @escaping (UUID) -> Bool = { _ in true },
        profile: @escaping (UUID) -> Profile? = { _ in nil },
        windowState: @escaping (UUID) -> BrowserWindowState? = { _ in nil },
        windows: @escaping () -> [(UUID, BrowserWindowState)] = { [] },
        windowStates: @escaping () -> [BrowserWindowState] = { [] },
        updateTabVisibility: @escaping () -> Void = { /* No-op. */ },
        webViewLifecycle: TabManagerWebViewLifecycleService? = nil,
        handleTabClosure: @escaping (UUID) -> Void = { _ in /* No-op. */ },
        visibleSplitTabIds: @escaping (UUID) -> [UUID] = { _ in [] },
        isTabVisibleInSplit: @escaping (UUID, UUID) -> Bool = { _, _ in false },
        isTabActiveInSplit: @escaping (UUID, UUID) -> Bool = { _, _ in false },
        updateActiveSplitSide: @escaping (UUID, UUID) -> Void = { _, _ in /* No-op. */ },
        notifyTabClosedIfLoaded: @escaping (Tab) -> Void = { _ in /* No-op. */ },
        notifyTabActivatedIfLoaded: @escaping (Tab, Tab?) -> Void = { _, _ in /* No-op. */ },
        captureClosedTab: @escaping (Tab, UUID?) -> Void = { _, _ in /* No-op. */ },
        captureDeletedShortcutLauncher: @escaping (ShortcutPin) -> Void = { _ in /* No-op. */ },
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)? = { nil },
        validateWindowStates: @escaping () -> Void = { /* No-op. */ },
        persistWindowSession: @escaping (BrowserWindowState) -> Void = { _ in /* No-op. */ },
        syncWorkspaceThemeAcrossWindows: @escaping (Space, Bool) -> Void = { _, _ in /* No-op. */ },
        closeAuxiliaryMiniWindow: @escaping (Tab, AuxiliaryWindowCloseReason) -> Void = { _, _ in /* No-op. */ },
        isLiveFolder: @escaping (UUID) -> Bool = { _ in false },
        deleteLiveFolderState: @escaping (Set<UUID>) -> Void = { _ in /* No-op. */ }
    ) -> RuntimePortRegistry {
        RuntimePortRegistry(
            profileQuery: ClosureTabProfileQueryPort(
                currentProfileId: currentProfileId,
                defaultProfileId: defaultProfileId,
                settings: settings,
                profileExists: profileExists,
                profile: profile
            ),
            windowQuery: ClosureTabWindowQueryPort(
                windowState: windowState,
                windows: windows,
                windowStates: windowStates,
                updateTabVisibility: updateTabVisibility,
                validateWindowStates: validateWindowStates,
                persistWindowSession: persistWindowSession,
                syncWorkspaceThemeAcrossWindows: syncWorkspaceThemeAcrossWindows
            ),
            splitCoordination: ClosureTabSplitCoordinationPort(
                handleTabClosure: handleTabClosure,
                visibleSplitTabIds: visibleSplitTabIds,
                isTabVisibleInSplit: isTabVisibleInSplit,
                isTabActiveInSplit: isTabActiveInSplit,
                updateActiveSplitSide: updateActiveSplitSide
            ),
            extensionLifecycle: ClosureTabExtensionLifecyclePort(
                notifyTabClosedIfLoaded: notifyTabClosedIfLoaded,
                notifyTabActivatedIfLoaded: notifyTabActivatedIfLoaded
            ),
            sessionSideEffects: ClosureTabSessionSideEffectsPort(
                captureClosedTab: captureClosedTab,
                captureDeletedShortcutLauncher: captureDeletedShortcutLauncher,
                notifications: notifications,
                closeAuxiliaryMiniWindow: closeAuxiliaryMiniWindow,
                isLiveFolder: isLiveFolder,
                deleteLiveFolderState: deleteLiveFolderState
            ),
            webViewLifecycle: webViewLifecycle ?? self.webViewLifecycle()
        )
    }

    static var inactive: RuntimePortRegistry { make() }
}

@MainActor
private final class ClosureTabProfileQueryPort: TabProfileQueryPort {
    private let currentProfileIdProvider: () -> UUID?
    private let defaultProfileIdProvider: () -> UUID?
    private let settingsProvider: () -> SumiSettingsService?
    private let profileExistsHandler: (UUID) -> Bool
    private let profileProvider: (UUID) -> Profile?

    init(
        currentProfileId: @escaping () -> UUID?,
        defaultProfileId: @escaping () -> UUID?,
        settings: @escaping () -> SumiSettingsService?,
        profileExists: @escaping (UUID) -> Bool,
        profile: @escaping (UUID) -> Profile?
    ) {
        self.currentProfileIdProvider = currentProfileId
        self.defaultProfileIdProvider = defaultProfileId
        self.settingsProvider = settings
        self.profileExistsHandler = profileExists
        self.profileProvider = profile
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
}

@MainActor
private final class ClosureTabWindowQueryPort: TabWindowQueryPort {
    private let windowStateProvider: (UUID) -> BrowserWindowState?
    private let windowsProvider: () -> [(UUID, BrowserWindowState)]
    private let windowStatesProvider: () -> [BrowserWindowState]
    private let updateTabVisibilityHandler: () -> Void
    private let validateWindowStatesHandler: () -> Void
    private let persistWindowSessionHandler: (BrowserWindowState) -> Void
    private let syncWorkspaceThemeAcrossWindowsHandler: (Space, Bool) -> Void

    init(
        windowState: @escaping (UUID) -> BrowserWindowState?,
        windows: @escaping () -> [(UUID, BrowserWindowState)],
        windowStates: @escaping () -> [BrowserWindowState],
        updateTabVisibility: @escaping () -> Void,
        validateWindowStates: @escaping () -> Void,
        persistWindowSession: @escaping (BrowserWindowState) -> Void,
        syncWorkspaceThemeAcrossWindows: @escaping (Space, Bool) -> Void
    ) {
        self.windowStateProvider = windowState
        self.windowsProvider = windows
        self.windowStatesProvider = windowStates
        self.updateTabVisibilityHandler = updateTabVisibility
        self.validateWindowStatesHandler = validateWindowStates
        self.persistWindowSessionHandler = persistWindowSession
        self.syncWorkspaceThemeAcrossWindowsHandler = syncWorkspaceThemeAcrossWindows
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

    func validateWindowStates() {
        validateWindowStatesHandler()
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        persistWindowSessionHandler(windowState)
    }

    func syncWorkspaceThemeAcrossWindows(for space: Space, animate: Bool) {
        syncWorkspaceThemeAcrossWindowsHandler(space, animate)
    }
}

@MainActor
private final class ClosureTabSplitCoordinationPort: TabSplitCoordinationPort {
    private let handleTabClosureHandler: (UUID) -> Void
    private let visibleSplitTabIdsProvider: (UUID) -> [UUID]
    private let isTabVisibleInSplitProvider: (UUID, UUID) -> Bool
    private let isTabActiveInSplitProvider: (UUID, UUID) -> Bool
    private let updateActiveSplitSideHandler: (UUID, UUID) -> Void

    init(
        handleTabClosure: @escaping (UUID) -> Void,
        visibleSplitTabIds: @escaping (UUID) -> [UUID],
        isTabVisibleInSplit: @escaping (UUID, UUID) -> Bool,
        isTabActiveInSplit: @escaping (UUID, UUID) -> Bool,
        updateActiveSplitSide: @escaping (UUID, UUID) -> Void
    ) {
        self.handleTabClosureHandler = handleTabClosure
        self.visibleSplitTabIdsProvider = visibleSplitTabIds
        self.isTabVisibleInSplitProvider = isTabVisibleInSplit
        self.isTabActiveInSplitProvider = isTabActiveInSplit
        self.updateActiveSplitSideHandler = updateActiveSplitSide
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
}

@MainActor
private final class ClosureTabExtensionLifecyclePort: TabExtensionLifecyclePort {
    private let notifyTabClosedIfLoadedHandler: (Tab) -> Void
    private let notifyTabActivatedIfLoadedHandler: (Tab, Tab?) -> Void

    init(
        notifyTabClosedIfLoaded: @escaping (Tab) -> Void,
        notifyTabActivatedIfLoaded: @escaping (Tab, Tab?) -> Void
    ) {
        self.notifyTabClosedIfLoadedHandler = notifyTabClosedIfLoaded
        self.notifyTabActivatedIfLoadedHandler = notifyTabActivatedIfLoaded
    }

    func notifyTabClosedIfLoaded(_ tab: Tab) {
        notifyTabClosedIfLoadedHandler(tab)
    }

    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?) {
        notifyTabActivatedIfLoadedHandler(newTab, previous)
    }
}

@MainActor
private final class ClosureTabSessionSideEffectsPort: TabSessionSideEffectsPort {
    private let captureClosedTabHandler: (Tab, UUID?) -> Void
    private let captureDeletedShortcutLauncherHandler: (ShortcutPin) -> Void
    private let notificationsProvider: @MainActor () -> (any BrowserNotificationPresenting)?
    private let closeAuxiliaryMiniWindowHandler: (Tab, AuxiliaryWindowCloseReason) -> Void
    private let isLiveFolderProvider: (UUID) -> Bool
    private let deleteLiveFolderStateHandler: (Set<UUID>) -> Void

    init(
        captureClosedTab: @escaping (Tab, UUID?) -> Void,
        captureDeletedShortcutLauncher: @escaping (ShortcutPin) -> Void,
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)?,
        closeAuxiliaryMiniWindow: @escaping (Tab, AuxiliaryWindowCloseReason) -> Void,
        isLiveFolder: @escaping (UUID) -> Bool,
        deleteLiveFolderState: @escaping (Set<UUID>) -> Void
    ) {
        self.captureClosedTabHandler = captureClosedTab
        self.captureDeletedShortcutLauncherHandler = captureDeletedShortcutLauncher
        self.notificationsProvider = notifications
        self.closeAuxiliaryMiniWindowHandler = closeAuxiliaryMiniWindow
        self.isLiveFolderProvider = isLiveFolder
        self.deleteLiveFolderStateHandler = deleteLiveFolderState
    }

    func captureClosedTab(_ tab: Tab, sourceSpaceId: UUID?) {
        captureClosedTabHandler(tab, sourceSpaceId)
    }

    func captureDeletedShortcutLauncher(_ pin: ShortcutPin) {
        captureDeletedShortcutLauncherHandler(pin)
    }

    func notifications() -> (any BrowserNotificationPresenting)? {
        notificationsProvider()
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
