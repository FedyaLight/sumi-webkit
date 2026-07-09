import Foundation

@MainActor
final class BrowserWindowSessionActivationOwner {
    private let windowSessionService: WindowSessionService
    private let runtime: @MainActor () -> WindowSessionRuntime?
    private let refreshSplitPublishedState: @MainActor (UUID) -> Void
    private let updateFindManagerCurrentTab: @MainActor () -> Void
    private let notifyExtensionWindowOpened: @MainActor (BrowserWindowState) -> Void
    private let notifyExtensionWindowFocused: @MainActor (BrowserWindowState) -> Void
    private let reconcileStartupSessionIfPossible: @MainActor () -> Void
    private let adoptProfileForWindowActivation: @MainActor (BrowserWindowState) -> Void
    private let scheduleNativeNowPlayingRefresh: @MainActor (UInt64) -> Void
    private let scheduleBackgroundMediaReconcile: @MainActor (String) -> Void
    private let pauseGeolocationOnAppBackgroundIfNeeded: @MainActor () -> Void
    private let resumeGeolocationOnAppForegroundIfNeeded: @MainActor () -> Void
    private let refreshLastSessionWindowsStore: @MainActor () -> Void

    init(
        windowSessionService: WindowSessionService,
        runtime: @escaping @MainActor () -> WindowSessionRuntime?,
        refreshSplitPublishedState: @escaping @MainActor (UUID) -> Void,
        updateFindManagerCurrentTab: @escaping @MainActor () -> Void,
        notifyExtensionWindowOpened: @escaping @MainActor (BrowserWindowState) -> Void,
        notifyExtensionWindowFocused: @escaping @MainActor (BrowserWindowState) -> Void,
        reconcileStartupSessionIfPossible: @escaping @MainActor () -> Void,
        adoptProfileForWindowActivation: @escaping @MainActor (BrowserWindowState) -> Void,
        scheduleNativeNowPlayingRefresh: @escaping @MainActor (UInt64) -> Void,
        scheduleBackgroundMediaReconcile: @escaping @MainActor (String) -> Void,
        pauseGeolocationOnAppBackgroundIfNeeded: @escaping @MainActor () -> Void,
        resumeGeolocationOnAppForegroundIfNeeded: @escaping @MainActor () -> Void,
        refreshLastSessionWindowsStore: @escaping @MainActor () -> Void
    ) {
        self.windowSessionService = windowSessionService
        self.runtime = runtime
        self.refreshSplitPublishedState = refreshSplitPublishedState
        self.updateFindManagerCurrentTab = updateFindManagerCurrentTab
        self.notifyExtensionWindowOpened = notifyExtensionWindowOpened
        self.notifyExtensionWindowFocused = notifyExtensionWindowFocused
        self.reconcileStartupSessionIfPossible = reconcileStartupSessionIfPossible
        self.adoptProfileForWindowActivation = adoptProfileForWindowActivation
        self.scheduleNativeNowPlayingRefresh = scheduleNativeNowPlayingRefresh
        self.scheduleBackgroundMediaReconcile = scheduleBackgroundMediaReconcile
        self.pauseGeolocationOnAppBackgroundIfNeeded = pauseGeolocationOnAppBackgroundIfNeeded
        self.resumeGeolocationOnAppForegroundIfNeeded = resumeGeolocationOnAppForegroundIfNeeded
        self.refreshLastSessionWindowsStore = refreshLastSessionWindowsStore
    }

    func setupWindowState(_ windowState: BrowserWindowState) {
        guard let runtime = runtime() else { return }
        windowSessionService.setupWindowState(
            windowState,
            runtime: runtime
        )
        notifyExtensionWindowOpened(windowState)
        reconcileStartupSessionIfPossible()
    }

    func setActiveWindowState(_ windowState: BrowserWindowState) {
        guard let runtime = runtime() else { return }
        refreshSplitPublishedState(windowState.id)
        windowSessionService.setActiveWindowState(
            windowState,
            runtime: runtime
        )
        updateFindManagerCurrentTab()
        notifyExtensionWindowFocused(windowState)
        adoptProfileForWindowActivation(windowState)
        scheduleNativeNowPlayingRefresh(0)
        scheduleBackgroundMediaReconcile("window-activated")
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        persistWindowSessionNow(for: windowState)
    }

    func schedulePersistWindowSession(
        for windowState: BrowserWindowState,
        delayNanoseconds: UInt64 = 450_000_000
    ) {
        windowSessionService.schedulePersistWindowSession(
            for: windowState,
            delayNanoseconds: delayNanoseconds
        ) { [weak self] windowState in
            self?.persistWindowSessionNow(for: windowState)
        }
    }

    func flushPendingWindowSessionPersistence() {
        windowSessionService.flushPendingWindowSessionPersistence { [weak self] windowState in
            self?.persistWindowSessionNow(for: windowState)
        }
    }

    func handleApplicationWillResignActive() {
        scheduleBackgroundMediaReconcile("app-will-resign-active")
        pauseGeolocationOnAppBackgroundIfNeeded()
    }

    func handleApplicationDidBecomeActive() {
        scheduleBackgroundMediaReconcile("app-did-become-active")
        resumeGeolocationOnAppForegroundIfNeeded()
    }

    func handleWindowVisibilityChanged(_ windowState: BrowserWindowState) {
        _ = windowState
        scheduleBackgroundMediaReconcile("window-visibility-changed")
    }

    private func persistWindowSessionNow(for windowState: BrowserWindowState) {
        guard let runtime = runtime() else { return }
        let signpostState = PerformanceTrace.beginInterval("WindowSession.persist")
        defer {
            PerformanceTrace.endInterval("WindowSession.persist", signpostState)
        }

        windowSessionService.persistWindowSession(
            for: windowState,
            runtime: runtime
        )
        refreshLastSessionWindowsStore()
    }
}

@MainActor
enum WindowSessionRuntimeFactory {
    static func make(for browserManager: BrowserManager) -> WindowSessionRuntime {
        WindowSessionRuntime(
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            tabManager: browserManager.tabManager,
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            splitManager: browserManager.splitManager,
            glanceManager: browserManager.glanceManager,
            shellSelectionService: browserManager.shellSelectionService,
            hasValidCurrentSelection: { [weak browserManager] windowState in
                browserManager?.windowSpaceStateOwner.hasValidCurrentSelection(in: windowState) ?? false
            },
            applyTabSelection: { [weak browserManager] tab, windowState, updateSpaceFromTab, updateTheme, rememberSelection, persistSelection in
                browserManager?.applyTabSelection(
                    tab,
                    in: windowState,
                    updateSpaceFromTab: updateSpaceFromTab,
                    updateTheme: updateTheme,
                    rememberSelection: rememberSelection,
                    persistSelection: persistSelection
                )
            },
            showEmptyState: { [weak browserManager] windowState in
                browserManager?.showEmptyState(in: windowState)
            },
            sanitizeFloatingBarState: { [weak browserManager] windowState in
                browserManager?.floatingBarRoutingOwner.sanitizeFloatingBarState(in: windowState)
            },
            syncShortcutSelectionState: { [weak browserManager] windowState in
                browserManager?.syncShortcutSelectionState(for: windowState)
            },
            commitWorkspaceTheme: { [weak browserManager] theme, windowState in
                browserManager?.workspaceThemeTransitionOwner.commitWorkspaceTheme(
                    theme,
                    for: windowState
                )
            },
            space: { [weak browserManager] spaceId in
                browserManager?.windowSpaceStateOwner.space(for: spaceId)
            },
            syncSidebarPresentationState: { [weak browserManager] windowState in
                browserManager?.sidebarPresentationOwner.syncFromWindow( windowState)
            },
            focusSplitGroup: { [weak browserManager] group, windowState in
                browserManager?.sidebarCommandService.splitShortcutRouting.focusSplitGroup(
                    group,
                    in: windowState
                )
            }
        )
    }
}
