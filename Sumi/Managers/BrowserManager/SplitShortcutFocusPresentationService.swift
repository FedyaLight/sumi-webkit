import Foundation

@MainActor
final class SplitShortcutFocusPresentationService {
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

    func apply(
        _ materialized: MaterializedWindowSplit,
        in windowState: BrowserWindowState
    ) {
        _ = selection.applyTabSelection(
            materialized.activeTab,
            in: windowState,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            persistSelection: false,
            loadPolicy: .immediate
        )
        windowState.splitSelection = materialized.presentation.selection
        visuals.refreshCompositor(for: windowState)
    }

    func persist(_ windowState: BrowserWindowState) {
        persistence.persist(windowState)
    }

    func refresh(_ windowState: BrowserWindowState) {
        visuals.refreshCompositor(for: windowState)
    }
}
