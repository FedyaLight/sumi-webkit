import Foundation

/// Owns the persisted last-session window archive. While the manual startup
/// restore offer is still live it re-commits the startup archive verbatim;
/// otherwise it archives the currently open regular windows, consuming the
/// offer once the user demonstrably works in multiple windows again.
@MainActor
final class LastSessionWindowArchive {
    struct RestoreAttempt: Equatable {
        fileprivate let id: UUID
        fileprivate let sourceWindowOrder: [UUID]
    }

    enum RestoreAttemptOutcome {
        case completed
        case interrupted
    }

    private let openWindows: OpenWindowSessionCatalog
    private let lastSessionWindowsStore: LastSessionWindowsStore
    private let startupRestore: any BrowserStartupSessionRestoreProviding
    private var activeRestoreAttempt: RestoreAttempt?
    private var restoreAttemptWaiters: [CheckedContinuation<RestoreAttempt, Never>] = []

    init(
        openWindows: OpenWindowSessionCatalog,
        lastSessionWindowsStore: LastSessionWindowsStore,
        startupRestore: any BrowserStartupSessionRestoreProviding
    ) {
        self.openWindows = openWindows
        self.lastSessionWindowsStore = lastSessionWindowsStore
        self.startupRestore = startupRestore
    }

    var canRestoreLastSession: Bool {
        lastSessionWindowsStore.canRestoreLastSession
    }

    var archivedWindowSnapshots: [LastSessionWindowSnapshot] {
        lastSessionWindowsStore.snapshots
    }

    var archivedTabSnapshot: TabPersistenceSnapshot? {
        lastSessionWindowsStore.tabSnapshot
    }

    /// Freezes the retry source while a multi-window restore is in flight.
    /// Activation and persistence callbacks may still request refreshes, but
    /// they cannot replace the source archive before the batch outcome is known.
    func beginRestoreAttempt() -> RestoreAttempt? {
        guard activeRestoreAttempt == nil else { return nil }
        let attempt = RestoreAttempt(
            id: UUID(),
            sourceWindowOrder: lastSessionWindowsStore.snapshots.map(\.id)
        )
        activeRestoreAttempt = attempt
        return attempt
    }

    /// Suspends behind an in-flight restore without polling or losing the
    /// caller's one-shot startup command. A cancelled waiter still receives a
    /// lease and must finish it as interrupted, keeping queue ownership exact.
    func acquireRestoreAttempt() async -> RestoreAttempt {
        if let attempt = beginRestoreAttempt() {
            return attempt
        }
        return await withCheckedContinuation { continuation in
            restoreAttemptWaiters.append(continuation)
        }
    }

    func finishRestoreAttempt(
        _ attempt: RestoreAttempt,
        outcome: RestoreAttemptOutcome
    ) {
        precondition(
            activeRestoreAttempt == attempt,
            "Last-session restore attempt finished with a stale archive lease"
        )
        activeRestoreAttempt = nil
        if case .completed = outcome {
            refreshNow(
                excludingWindowID: nil,
                preservingWindowOrder: attempt.sourceWindowOrder,
                enqueuePersistence: true
            )
        }
        resumeNextRestoreAttemptIfNeeded()
    }

    func refresh(excludingWindowID: UUID?) {
        guard activeRestoreAttempt == nil else { return }
        refreshNow(excludingWindowID: excludingWindowID)
    }

    func refresh(using snapshots: [LastSessionWindowSnapshot]) {
        guard activeRestoreAttempt == nil else { return }
        refreshNow(
            excludingWindowID: nil,
            liveSnapshots: snapshots
        )
    }

    func enqueueRefresh(excludingWindowID: UUID?) {
        guard activeRestoreAttempt == nil else { return }
        refreshNow(
            excludingWindowID: excludingWindowID,
            enqueuePersistence: true
        )
    }

    func enqueueRefresh(using snapshots: [LastSessionWindowSnapshot]) {
        guard activeRestoreAttempt == nil else { return }
        refreshNow(
            excludingWindowID: nil,
            liveSnapshots: snapshots,
            enqueuePersistence: true
        )
    }

    func flushPendingPersistence() {
        lastSessionWindowsStore.flushPendingPersistence()
    }

    private func refreshNow(
        excludingWindowID: UUID?,
        preservingWindowOrder: [UUID] = [],
        liveSnapshots: [LastSessionWindowSnapshot]? = nil,
        enqueuePersistence: Bool = false
    ) {
        if startupRestore.canOfferRestoreShortcut {
            if enqueuePersistence {
                lastSessionWindowsStore.enqueueUpdateSnapshots(
                    startupRestore.windowSnapshots,
                    tabSnapshot: startupRestore.tabSnapshot
                )
            } else {
                lastSessionWindowsStore.updateSnapshots(
                    startupRestore.windowSnapshots,
                    tabSnapshot: startupRestore.tabSnapshot
                )
            }
            return
        }

        var snapshots = liveSnapshots ?? openWindows.regularWindowSnapshots(
            excludingWindowID: excludingWindowID
        )
        if snapshots.isEmpty,
           let excludingWindowID,
           openWindows.deterministicRegularWindow(excludingWindowID: excludingWindowID) == nil {
            snapshots = openWindows.regularWindowSnapshots(excludingWindowID: nil)
        }
        if snapshots.count > 1 {
            startupRestore.markRestoreOfferConsumed()
        }
        // A live projection is observational. A delayed persistence callback
        // can arrive after the final registry removal, and must not turn that
        // temporary absence into an explicit archive deletion.
        guard snapshots.isEmpty == false else { return }
        if preservingWindowOrder.isEmpty == false {
            let sourceRank = Dictionary(
                uniqueKeysWithValues: preservingWindowOrder.enumerated().map {
                    ($0.element, $0.offset)
                }
            )
            snapshots.sort { lhs, rhs in
                switch (sourceRank[lhs.id], sourceRank[rhs.id]) {
                case let (.some(lhsRank), .some(rhsRank)):
                    lhsRank < rhsRank
                case (.some, .none):
                    true
                case (.none, .some):
                    false
                case (.none, .none):
                    lhs.id.uuidString < rhs.id.uuidString
                }
            }
        }
        if enqueuePersistence {
            lastSessionWindowsStore.enqueueUpdateSnapshots(snapshots)
        } else {
            lastSessionWindowsStore.updateSnapshots(snapshots)
        }
    }

    private func resumeNextRestoreAttemptIfNeeded() {
        guard activeRestoreAttempt == nil,
              restoreAttemptWaiters.isEmpty == false else {
            return
        }
        let continuation = restoreAttemptWaiters.removeFirst()
        let attempt = RestoreAttempt(
            id: UUID(),
            sourceWindowOrder: lastSessionWindowsStore.snapshots.map(\.id)
        )
        activeRestoreAttempt = attempt
        continuation.resume(returning: attempt)
    }
}
