import Foundation

/// Coordinates immediate and coalesced window-session commits. Live commits
/// refresh the last-session window archive; root teardown preserves that
/// last valid archive while flushing only the primary durable snapshot.
@MainActor
final class WindowSessionPersistenceCoordinator {
    private let snapshotStore: WindowSessionSnapshotStore
    private let snapshotFactory: WindowSessionSnapshotFactory
    private let scheduler: WindowSessionPersistenceScheduler
    private let openWindows: OpenWindowSessionCatalog
    private let archive: LastSessionWindowArchive

    init(
        snapshotStore: WindowSessionSnapshotStore,
        snapshotFactory: WindowSessionSnapshotFactory,
        scheduler: WindowSessionPersistenceScheduler,
        openWindows: OpenWindowSessionCatalog,
        archive: LastSessionWindowArchive
    ) {
        self.snapshotStore = snapshotStore
        self.snapshotFactory = snapshotFactory
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

        // An immediate live projection supersedes the whole coalesced batch:
        // every pending write targets the same legacy primary key.
        scheduler.cancelAll()
        let durablePrimary = regularWindowStates.max {
            $0.id.uuidString < $1.id.uuidString
        }
        commitLiveProjection(
            durablePrimary: durablePrimary,
            excludingWindowID: nil
        )
    }

    /// Establishes the durable primary before WindowRegistry removes the
    /// closing state and can advance the global restore cycle. The exact
    /// closing write is cancelled synchronously: it can never reappear during
    /// a later scheduler flush.
    func persistBeforeClosing(_ windowState: BrowserWindowState) {
        guard windowState.isIncognito == false else {
            scheduler.cancel(for: windowState.id)
            return
        }
        // Closing commits a complete live projection before registry removal.
        // No older per-window request may overwrite its chosen survivor later.
        scheduler.cancelAll()

        let durablePrimary = openWindows.deterministicRegularWindow(
            excludingWindowID: windowState.id
        ) ?? windowState
        commitLiveProjection(
            durablePrimary: durablePrimary,
            excludingWindowID: windowState.id
        )
    }

    func schedule(
        _ windowState: BrowserWindowState,
        delayNanoseconds: UInt64 = 450_000_000
    ) {
        scheduler.schedule(
            WindowSessionDurableWrite(
                windowState: windowState,
                store: snapshotStore,
                snapshotFactory: snapshotFactory
            ),
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

    private func commitLiveProjection(
        durablePrimary: BrowserWindowState?,
        excludingWindowID: UUID?
    ) {
        let allProjection = openWindows.regularWindowProjection()
        var archiveProjection = allProjection.filter {
            $0.windowState.id != excludingWindowID
        }
        if archiveProjection.isEmpty, allProjection.isEmpty == false {
            archiveProjection = allProjection
        }

        if let durablePrimary {
            let durableSnapshot = allProjection.first {
                $0.windowState === durablePrimary
            }?.archiveSnapshot.session
                ?? snapshotFactory.make(for: durablePrimary)
            _ = snapshotStore.persist(durableSnapshot)
        }
        archive.refresh(
            using: archiveProjection.map(\.archiveSnapshot)
        )
    }
}
