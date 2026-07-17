import Foundation

/// Supplies ContentView with the exact persistence authority needed by a
/// window's SwiftUI disappear lifecycle.
@MainActor
final class BrowserWindowLifecycleService: BrowserWindowLifecycleHandling {
    private let persistence: WindowSessionPersistenceCoordinator

    init(persistence: WindowSessionPersistenceCoordinator) {
        self.persistence = persistence
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        persistence.persist(windowState)
    }
}
