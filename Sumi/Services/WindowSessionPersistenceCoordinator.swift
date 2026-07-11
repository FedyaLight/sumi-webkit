import Foundation

/// Coordinates immediate and coalesced window-session commits. Live commits
/// refresh the last-session window archive; root teardown preserves that
/// last valid archive while flushing only the primary durable snapshot.
@MainActor
final class WindowSessionPersistenceCoordinator {
    private let persistence: WindowSessionPersistenceService
    private let scheduler: WindowSessionPersistenceScheduler
    private let openWindows: OpenWindowSessionCatalog
    private let archive: LastSessionWindowArchive

    init(
        persistence: WindowSessionPersistenceService,
        scheduler: WindowSessionPersistenceScheduler,
        openWindows: OpenWindowSessionCatalog,
        archive: LastSessionWindowArchive
    ) {
        self.persistence = persistence
        self.scheduler = scheduler
        self.openWindows = openWindows
        self.archive = archive
    }

    func persist(_ windowState: BrowserWindowState) {
        persist([windowState])
    }

    func persist(_ windowStates: [BrowserWindowState]) {
        let regularWindowStates = windowStates.filter { $0.isIncognito == false }
        guard regularWindowStates.isEmpty == false else { return }
        let trace = PerformanceTrace.beginInterval("WindowSession.persist")
        defer {
            PerformanceTrace.endInterval("WindowSession.persist", trace)
        }

        for windowState in regularWindowStates {
            scheduler.cancel(for: windowState.id)
            persistence.persistDurableSnapshot(windowState)
        }
        archive.refresh(excludingWindowID: nil)
    }

    /// Establishes the durable primary before WindowRegistry removes the
    /// closing state and can advance the global restore cycle. The exact
    /// closing write is cancelled synchronously: it can never reappear during
    /// a later scheduler flush.
    func persistBeforeClosing(_ windowState: BrowserWindowState) {
        scheduler.cancel(for: windowState.id)
        guard windowState.isIncognito == false else { return }

        let durablePrimary = openWindows.deterministicRegularWindow(
            excludingWindowID: windowState.id
        ) ?? windowState
        scheduler.cancel(for: durablePrimary.id)
        persistence.persistDurableSnapshot(durablePrimary)
        archive.refresh(excludingWindowID: windowState.id)
    }

    func schedule(
        _ windowState: BrowserWindowState,
        delayNanoseconds: UInt64 = 450_000_000
    ) {
        scheduler.schedule(
            persistence.durableWrite(for: windowState),
            delayNanoseconds: delayNanoseconds,
            afterDurableCommit: { [archive] in
                archive.refresh(excludingWindowID: nil)
            }
        )
    }

    @discardableResult
    func flush() -> Int {
        let committedWriteCount = scheduler.flush()
        guard committedWriteCount > 0 else { return 0 }
        archive.refresh(excludingWindowID: nil)
        return committedWriteCount
    }
}
