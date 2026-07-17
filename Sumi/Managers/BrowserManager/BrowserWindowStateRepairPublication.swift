import Foundation

@MainActor
final class BrowserWindowStateRepairPublication {
    private let persistence: WindowSessionPersistenceCoordinator
    private let visuals: BrowserWindowVisualCoordinator

    init(
        persistence: WindowSessionPersistenceCoordinator,
        visuals: BrowserWindowVisualCoordinator
    ) {
        self.persistence = persistence
        self.visuals = visuals
    }

    func publish(_ windowState: BrowserWindowState) {
        visuals.refreshCompositor(for: windowState)
        persistence.persist(windowState)
    }
}
