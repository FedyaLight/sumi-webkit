import Foundation

@MainActor
final class BrowserWindowSessionActivationOwner {
    struct Dependencies {
        let windowSessionService: WindowSessionService
        let delegate: @MainActor () -> WindowSessionServiceDelegate
        let refreshSplitPublishedState: @MainActor (UUID) -> Void
        let updateFindManagerCurrentTab: @MainActor () -> Void
        let notifyExtensionWindowOpened: @MainActor (BrowserWindowState) -> Void
        let notifyExtensionWindowFocused: @MainActor (BrowserWindowState) -> Void
        let reconcileStartupSessionIfPossible: @MainActor () -> Void
        let adoptProfileForWindowActivation: @MainActor (BrowserWindowState) -> Void
        let scheduleNativeNowPlayingRefresh: @MainActor (UInt64) -> Void
        let scheduleBackgroundMediaReconcile: @MainActor (String) -> Void
        let pauseGeolocationForApplicationBackgroundIfNeeded: @MainActor () -> Void
        let resumeGeolocationForApplicationForegroundIfNeeded: @MainActor () -> Void
        let refreshLastSessionWindowsStore: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func setupWindowState(_ windowState: BrowserWindowState) {
        dependencies.windowSessionService.setupWindowState(
            windowState,
            delegate: dependencies.delegate()
        )
        dependencies.notifyExtensionWindowOpened(windowState)
        dependencies.reconcileStartupSessionIfPossible()
    }

    func setActiveWindowState(_ windowState: BrowserWindowState) {
        dependencies.refreshSplitPublishedState(windowState.id)
        dependencies.windowSessionService.setActiveWindowState(
            windowState,
            delegate: dependencies.delegate()
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
        dependencies.pauseGeolocationForApplicationBackgroundIfNeeded()
    }

    func handleApplicationDidBecomeActive() {
        dependencies.scheduleBackgroundMediaReconcile("app-did-become-active")
        dependencies.resumeGeolocationForApplicationForegroundIfNeeded()
    }

    func handleWindowVisibilityChanged(_ windowState: BrowserWindowState) {
        _ = windowState
        dependencies.scheduleBackgroundMediaReconcile("window-visibility-changed")
    }

    private func persistWindowSessionNow(for windowState: BrowserWindowState) {
        let signpostState = PerformanceTrace.beginInterval("WindowSession.persist")
        defer {
            PerformanceTrace.endInterval("WindowSession.persist", signpostState)
        }

        dependencies.windowSessionService.persistWindowSession(
            for: windowState,
            delegate: dependencies.delegate()
        )
        dependencies.refreshLastSessionWindowsStore()
    }
}
