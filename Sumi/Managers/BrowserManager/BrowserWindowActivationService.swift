import Foundation

/// Applies effects that belong specifically to changing the focused or visible
/// browser window. Restore and persistence scheduling live elsewhere.
@MainActor
final class BrowserWindowActivationService {
    private struct DeferredActivation {
        let windowIdentity: ObjectIdentifier
    }

    private let sidebarPresentation: BrowserSidebarPresentationOwner
    private let persistence: WindowSessionPersistenceCoordinator
    private let activePageResolver: ActivePageResolver
    private let findManager: FindManager
    private let extensions: any BrowserWindowExtensionFocusNotifying
    private let synchronizeFocusedContext: (BrowserWindowState) -> Void
    private let nowPlaying: any SumiNativeNowPlayingRuntimeControlling
    private let backgroundMedia: SumiBackgroundMediaOptimizationService
    private var deferredActivationsByWindowID: [UUID: DeferredActivation] = [:]

    init(
        sidebarPresentation: BrowserSidebarPresentationOwner,
        persistence: WindowSessionPersistenceCoordinator,
        activePageResolver: ActivePageResolver,
        findManager: FindManager,
        extensions: any BrowserWindowExtensionFocusNotifying,
        synchronizeFocusedContext: @escaping (BrowserWindowState) -> Void,
        nowPlaying: any SumiNativeNowPlayingRuntimeControlling,
        backgroundMedia: SumiBackgroundMediaOptimizationService
    ) {
        self.sidebarPresentation = sidebarPresentation
        self.persistence = persistence
        self.activePageResolver = activePageResolver
        self.findManager = findManager
        self.extensions = extensions
        self.synchronizeFocusedContext = synchronizeFocusedContext
        self.nowPlaying = nowPlaying
        self.backgroundMedia = backgroundMedia
    }

    func activate(_ windowState: BrowserWindowState) {
        guard windowState.isAwaitingInitialSessionResolution == false else {
            deferredActivationsByWindowID[windowState.id] = DeferredActivation(
                windowIdentity: ObjectIdentifier(windowState)
            )
            return
        }

        deferredActivationsByWindowID.removeValue(forKey: windowState.id)
        applyActivation(windowState)
    }

    /// Completes a deferred focus transition only for the exact object that is
    /// still active after initial session resolution. Repeated completion is
    /// intentionally a no-op.
    func completeDeferredActivation(
        for activeWindow: BrowserWindowState?
    ) {
        guard let activeWindow,
              let deferred = deferredActivationsByWindowID[activeWindow.id],
              deferred.windowIdentity == ObjectIdentifier(activeWindow)
        else {
            deferredActivationsByWindowID.removeAll()
            return
        }
        guard activeWindow.isAwaitingInitialSessionResolution == false else {
            return
        }

        deferredActivationsByWindowID.removeAll()
        applyActivation(activeWindow)
    }

    func discardDeferredActivation(_ windowState: BrowserWindowState) {
        guard deferredActivationsByWindowID[windowState.id]?.windowIdentity
                == ObjectIdentifier(windowState)
        else {
            return
        }
        deferredActivationsByWindowID.removeValue(forKey: windowState.id)
    }

    private func applyActivation(_ windowState: BrowserWindowState) {
        synchronizeFocusedContext(windowState)
        sidebarPresentation.syncFromWindow(windowState)
        persistence.persist(windowState)

        let page = activePageResolver.resolve(in: windowState)
        findManager.updateCurrentTab(page?.tab, in: windowState.id)
        extensions.notifyWindowFocusedIfLoaded(windowState)

        nowPlaying.scheduleRefresh(delayNanoseconds: 0)
        backgroundMedia.scheduleReconcile(reason: "window-activated")
    }

    func handleVisibilityChanged(_ windowState: BrowserWindowState) {
        _ = windowState
        backgroundMedia.scheduleReconcile(reason: "window-visibility-changed")
    }
}
