import Foundation

/// Applies effects that belong specifically to changing the focused or visible
/// browser window. Restore and persistence scheduling live elsewhere.
@MainActor
final class BrowserWindowActivationService {
    private let splitManager: SplitViewManager
    private let sidebarPresentation: BrowserSidebarPresentationOwner
    private let persistence: WindowSessionPersistenceCoordinator
    private let activePageRouting: BrowserActivePageRoutingOwner
    private let findManager: FindManager
    private let extensions: SumiExtensionsModule
    private let profileRouter: SumiProfileRouter
    private weak var profileSupport: (any SumiProfileRoutingSupport)?
    private let nowPlaying: any SumiNativeNowPlayingRuntimeControlling
    private let backgroundMedia: SumiBackgroundMediaOptimizationService

    init(
        splitManager: SplitViewManager,
        sidebarPresentation: BrowserSidebarPresentationOwner,
        persistence: WindowSessionPersistenceCoordinator,
        activePageRouting: BrowserActivePageRoutingOwner,
        findManager: FindManager,
        extensions: SumiExtensionsModule,
        profileRouter: SumiProfileRouter,
        profileSupport: any SumiProfileRoutingSupport,
        nowPlaying: any SumiNativeNowPlayingRuntimeControlling,
        backgroundMedia: SumiBackgroundMediaOptimizationService
    ) {
        self.splitManager = splitManager
        self.sidebarPresentation = sidebarPresentation
        self.persistence = persistence
        self.activePageRouting = activePageRouting
        self.findManager = findManager
        self.extensions = extensions
        self.profileRouter = profileRouter
        self.profileSupport = profileSupport
        self.nowPlaying = nowPlaying
        self.backgroundMedia = backgroundMedia
    }

    func activate(_ windowState: BrowserWindowState) {
        splitManager.refreshPublishedState(for: windowState.id)
        sidebarPresentation.syncFromWindow(windowState)
        persistence.persist(windowState)

        let findSession = activePageRouting.activeFindSession()
        findManager.updateCurrentTab(findSession.tab, in: findSession.windowId)
        extensions.notifyWindowFocusedIfLoaded(windowState)

        if let profileSupport {
            profileRouter.adoptProfileIfNeeded(
                for: windowState,
                context: .windowActivation,
                support: profileSupport
            )
        }

        nowPlaying.scheduleRefresh(delayNanoseconds: 0)
        backgroundMedia.scheduleReconcile(reason: "window-activated")
    }

    func handleVisibilityChanged(_ windowState: BrowserWindowState) {
        _ = windowState
        backgroundMedia.scheduleReconcile(reason: "window-visibility-changed")
    }
}
