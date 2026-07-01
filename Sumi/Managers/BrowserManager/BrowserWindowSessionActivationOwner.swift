import Foundation

@MainActor
final class BrowserWindowSessionActivationOwner {
    struct Dependencies {
        let windowSessionService: WindowSessionService
        let runtime: @MainActor () -> WindowSessionRuntime?
        let refreshSplitPublishedState: @MainActor (UUID) -> Void
        let updateFindManagerCurrentTab: @MainActor () -> Void
        let notifyExtensionWindowOpened: @MainActor (BrowserWindowState) -> Void
        let notifyExtensionWindowFocused: @MainActor (BrowserWindowState) -> Void
        let reconcileStartupSessionIfPossible: @MainActor () -> Void
        let adoptProfileForWindowActivation: @MainActor (BrowserWindowState) -> Void
        let scheduleNativeNowPlayingRefresh: @MainActor (UInt64) -> Void
        let scheduleBackgroundMediaReconcile: @MainActor (String) -> Void
        let pauseGeolocationOnAppBackgroundIfNeeded: @MainActor () -> Void
        let resumeGeolocationOnAppForegroundIfNeeded: @MainActor () -> Void
        let refreshLastSessionWindowsStore: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func setupWindowState(_ windowState: BrowserWindowState) {
        guard let runtime = dependencies.runtime() else { return }
        dependencies.windowSessionService.setupWindowState(
            windowState,
            runtime: runtime
        )
        dependencies.notifyExtensionWindowOpened(windowState)
        dependencies.reconcileStartupSessionIfPossible()
    }

    func setActiveWindowState(_ windowState: BrowserWindowState) {
        guard let runtime = dependencies.runtime() else { return }
        dependencies.refreshSplitPublishedState(windowState.id)
        dependencies.windowSessionService.setActiveWindowState(
            windowState,
            runtime: runtime
        )
        dependencies.updateFindManagerCurrentTab()
        dependencies.notifyExtensionWindowFocused(windowState)
        dependencies.adoptProfileForWindowActivation(windowState)
        dependencies.scheduleNativeNowPlayingRefresh(0)
        dependencies.scheduleBackgroundMediaReconcile("window-activated")
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        persistWindowSessionNow(for: windowState)
    }

    func schedulePersistWindowSession(
        for windowState: BrowserWindowState,
        delayNanoseconds: UInt64 = 450_000_000
    ) {
        dependencies.windowSessionService.schedulePersistWindowSession(
            for: windowState,
            delayNanoseconds: delayNanoseconds
        ) { [weak self] windowState in
            self?.persistWindowSessionNow(for: windowState)
        }
    }

    func flushPendingWindowSessionPersistence() {
        dependencies.windowSessionService.flushPendingWindowSessionPersistence { [weak self] windowState in
            self?.persistWindowSessionNow(for: windowState)
        }
    }

    func handleApplicationWillResignActive() {
        dependencies.scheduleBackgroundMediaReconcile("app-will-resign-active")
        dependencies.pauseGeolocationOnAppBackgroundIfNeeded()
    }

    func handleApplicationDidBecomeActive() {
        dependencies.scheduleBackgroundMediaReconcile("app-did-become-active")
        dependencies.resumeGeolocationOnAppForegroundIfNeeded()
    }

    func handleWindowVisibilityChanged(_ windowState: BrowserWindowState) {
        _ = windowState
        dependencies.scheduleBackgroundMediaReconcile("window-visibility-changed")
    }

    private func persistWindowSessionNow(for windowState: BrowserWindowState) {
        guard let runtime = dependencies.runtime() else { return }
        let signpostState = PerformanceTrace.beginInterval("WindowSession.persist")
        defer {
            PerformanceTrace.endInterval("WindowSession.persist", signpostState)
        }

        dependencies.windowSessionService.persistWindowSession(
            for: windowState,
            runtime: runtime
        )
        dependencies.refreshLastSessionWindowsStore()
    }
}

extension BrowserManager {
    func makeWindowSessionRuntime() -> WindowSessionRuntime {
        WindowSessionRuntime(
            currentProfile: { [weak self] in
                self?.currentProfile
            },
            tabManager: tabManager,
            windowRegistry: { [weak self] in
                self?.windowRegistry
            },
            splitManager: splitManager,
            glanceManager: glanceManager,
            shellSelectionService: shellSelectionService,
            hasValidCurrentSelection: { [weak self] windowState in
                self?.hasValidCurrentSelection(in: windowState) ?? false
            },
            applyTabSelection: { [weak self] tab, windowState, updateSpaceFromTab, updateTheme, rememberSelection, persistSelection in
                self?.applyTabSelection(
                    tab,
                    in: windowState,
                    updateSpaceFromTab: updateSpaceFromTab,
                    updateTheme: updateTheme,
                    rememberSelection: rememberSelection,
                    persistSelection: persistSelection
                )
            },
            showEmptyState: { [weak self] windowState in
                self?.showEmptyState(in: windowState)
            },
            sanitizeFloatingBarState: { [weak self] windowState in
                self?.sanitizeFloatingBarState(in: windowState)
            },
            syncShortcutSelectionState: { [weak self] windowState in
                self?.syncShortcutSelectionState(for: windowState)
            },
            commitWorkspaceTheme: { [weak self] theme, windowState in
                self?.commitWorkspaceTheme(theme, for: windowState)
            },
            space: { [weak self] spaceId in
                self?.space(for: spaceId)
            },
            syncSidebarPresentationState: { [weak self] windowState in
                self?.syncSidebarPresentationState(from: windowState)
            },
            focusSplitGroup: { [weak self] group, windowState in
                self?.focusSplitGroup(group, in: windowState)
            }
        )
    }
}

extension BrowserWindowSessionActivationOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let windowSessionService = browserManager.windowSessionService
        let nativeNowPlayingController = browserManager.nativeNowPlayingController
        let backgroundMediaOptimizationService = browserManager.backgroundMediaOptimizationService
        let permissionRuntime = browserManager.permissionRuntime

        return Self(
            windowSessionService: windowSessionService,
            runtime: { [weak browserManager] in
                browserManager?.makeWindowSessionRuntime()
            },
            refreshSplitPublishedState: { [weak browserManager] windowId in
                browserManager?.splitManager.refreshPublishedState(for: windowId)
            },
            updateFindManagerCurrentTab: { [weak browserManager] in
                browserManager?.updateFindManagerCurrentTab()
            },
            notifyExtensionWindowOpened: { [weak browserManager] windowState in
                guard let browserManager else { return }
                BrowserManagerRuntimeWiring.notifyExtensionWindowOpened(windowState, for: browserManager)
            },
            notifyExtensionWindowFocused: { [weak browserManager] windowState in
                guard let browserManager else { return }
                BrowserManagerRuntimeWiring.notifyExtensionWindowFocused(windowState, for: browserManager)
            },
            reconcileStartupSessionIfPossible: { [weak browserManager] in
                browserManager?.reconcileStartupSessionIfPossible()
            },
            adoptProfileForWindowActivation: { [weak browserManager] windowState in
                browserManager?.adoptProfileForWindowActivation(windowState)
            },
            scheduleNativeNowPlayingRefresh: { delayNanoseconds in
                nativeNowPlayingController.scheduleRefresh(delayNanoseconds: delayNanoseconds)
            },
            scheduleBackgroundMediaReconcile: { reason in
                backgroundMediaOptimizationService.scheduleReconcile(reason: reason)
            },
            pauseGeolocationOnAppBackgroundIfNeeded: {
                permissionRuntime.pauseGeolocationOnAppBackgroundIfNeeded()
            },
            resumeGeolocationOnAppForegroundIfNeeded: {
                permissionRuntime.resumeGeolocationOnAppForegroundIfNeeded()
            },
            refreshLastSessionWindowsStore: { [weak browserManager] in
                browserManager?.refreshLastSessionWindowsStore(excludingWindowID: nil)
            }
        )
    }
}
