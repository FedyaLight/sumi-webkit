import Foundation

/// Coordinates immediate and coalesced window-session commits and keeps the
/// multi-window history snapshot in step with every durable commit.
@MainActor
final class WindowSessionPersistenceCoordinator {
    private let persistence: WindowSessionPersistenceService
    private let scheduler: WindowSessionPersistenceScheduler
    private let history: BrowserWindowHistorySessionOwner

    init(
        persistence: WindowSessionPersistenceService,
        scheduler: WindowSessionPersistenceScheduler,
        history: BrowserWindowHistorySessionOwner
    ) {
        self.persistence = persistence
        self.scheduler = scheduler
        self.history = history
    }

    func persist(_ windowState: BrowserWindowState) {
        let trace = PerformanceTrace.beginInterval("WindowSession.persist")
        defer {
            PerformanceTrace.endInterval("WindowSession.persist", trace)
        }

        persistence.persist(windowState)
        history.refreshLastSessionWindowsStore(excludingWindowID: nil)
    }

    func schedule(
        _ windowState: BrowserWindowState,
        delayNanoseconds: UInt64 = 450_000_000
    ) {
        scheduler.schedule(
            windowState,
            delayNanoseconds: delayNanoseconds
        ) { [weak self] windowState in
            self?.persist(windowState)
        }
    }

    func flush() {
        scheduler.flush { [weak self] windowState in
            self?.persist(windowState)
        }
    }
}
