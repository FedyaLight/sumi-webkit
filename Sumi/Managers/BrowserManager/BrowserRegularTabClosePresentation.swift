import Foundation

@MainActor
final class BrowserRegularTabClosePresentation {
    private let selection: BrowserTabSelectionOwner
    private let visuals: BrowserWindowVisualCoordinator
    private let persistence: WindowSessionPersistenceCoordinator

    init(
        selection: BrowserTabSelectionOwner,
        visuals: BrowserWindowVisualCoordinator,
        persistence: WindowSessionPersistenceCoordinator
    ) {
        self.selection = selection
        self.visuals = visuals
        self.persistence = persistence
    }

    func selectFallback(_ tab: Tab, in windowState: BrowserWindowState) {
        _ = selection.selectTab(tab, in: windowState, loadPolicy: .immediate)
        _ = visuals.performImmediateVisualHandoffIfPossible(in: windowState)
    }

    func showEmptyState(in windowState: BrowserWindowState) {
        selection.showEmptyState(in: windowState)
    }

    func persist(_ windowState: BrowserWindowState) {
        persistence.persist(windowState)
    }
}
