import Foundation

@MainActor
final class BrowserTabSelectionMediaEffects {
    private let nowPlaying: any SumiNativeNowPlayingRuntimeControlling
    private let findManager: FindManager
    private let activePage: ActivePageResolver
    private let windowVisuals: BrowserWindowVisualCoordinator

    init(
        nowPlaying: any SumiNativeNowPlayingRuntimeControlling,
        findManager: FindManager,
        activePage: ActivePageResolver,
        windowVisuals: BrowserWindowVisualCoordinator
    ) {
        self.nowPlaying = nowPlaying
        self.findManager = findManager
        self.activePage = activePage
        self.windowVisuals = windowVisuals
    }

    func prepare(_ tab: Tab) {
        nowPlaying.handleTabActivated(tab.id)
        tab.noteAccess()
    }

    func publish(_ tab: Tab, in windowState: BrowserWindowState) {
        Task { @MainActor [weak tab] in
            guard let tab else { return }
            await tab.fetchFaviconForVisiblePresentation()
        }
        nowPlaying.scheduleRefresh(delayNanoseconds: 0)
        updateFindManagerCurrentTab()
        windowVisuals.schedulePrepareVisibleWebViews(for: windowState)
        windowVisuals.refreshCompositor(for: windowState)
    }

    func publishEmptyState(in windowState: BrowserWindowState) {
        findManager.updateCurrentTab(nil, in: nil)
        windowVisuals.refreshCompositor(for: windowState)
    }

    private func updateFindManagerCurrentTab() {
        let page = activePage.resolveActiveWindow()
        findManager.updateCurrentTab(page?.tab, in: page?.windowState.id)
    }
}
