import Foundation

/// Owns the persisted last-session window archive. While the manual startup
/// restore offer is still live it re-commits the startup archive verbatim;
/// otherwise it archives the currently open regular windows, consuming the
/// offer once the user demonstrably works in multiple windows again.
@MainActor
final class LastSessionWindowArchive {
    struct RestoreAttempt: Equatable {
        fileprivate let id: UUID
    }

    enum RestoreAttemptOutcome {
        case completed
        case interrupted
    }

    private let openWindows: OpenWindowSessionCatalog
    private let lastSessionWindowsStore: @MainActor () -> LastSessionWindowsStore
    private let startupRestore: any BrowserStartupSessionRestoreProviding
    private var activeRestoreAttempt: RestoreAttempt?
    private var restoreAttemptWaiters: [CheckedContinuation<RestoreAttempt, Never>] = []

    init(
        openWindows: OpenWindowSessionCatalog,
        lastSessionWindowsStore: @escaping @MainActor () -> LastSessionWindowsStore,
        startupRestore: any BrowserStartupSessionRestoreProviding
    ) {
        self.openWindows = openWindows
        self.lastSessionWindowsStore = lastSessionWindowsStore
        self.startupRestore = startupRestore
    }

    var canRestoreLastSession: Bool {
        lastSessionWindowsStore().canRestoreLastSession
    }

    var archivedWindowSnapshots: [LastSessionWindowSnapshot] {
        lastSessionWindowsStore().snapshots
    }

    var archivedTabSnapshot: TabPersistenceSnapshot? {
        lastSessionWindowsStore().tabSnapshot
    }

    /// Freezes the retry source while a multi-window restore is in flight.
    /// Activation and persistence callbacks may still request refreshes, but
    /// they cannot replace the source archive before the batch outcome is known.
    func beginRestoreAttempt() -> RestoreAttempt? {
        guard activeRestoreAttempt == nil else { return nil }
        let attempt = RestoreAttempt(id: UUID())
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
            refreshNow(excludingWindowID: nil)
        }
        resumeNextRestoreAttemptIfNeeded()
    }

    func refresh(excludingWindowID: UUID?) {
        guard activeRestoreAttempt == nil else { return }
        refreshNow(excludingWindowID: excludingWindowID)
    }

    private func refreshNow(excludingWindowID: UUID?) {
        if startupRestore.canOfferRestoreShortcut {
            lastSessionWindowsStore().updateSnapshots(
                startupRestore.windowSnapshots,
                tabSnapshot: startupRestore.tabSnapshot
            )
            return
        }

        var snapshots = openWindows.regularWindowSnapshots(
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
        lastSessionWindowsStore().updateSnapshots(snapshots)
    }

    private func resumeNextRestoreAttemptIfNeeded() {
        guard activeRestoreAttempt == nil,
              restoreAttemptWaiters.isEmpty == false else {
            return
        }
        let continuation = restoreAttemptWaiters.removeFirst()
        let attempt = RestoreAttempt(id: UUID())
        activeRestoreAttempt = attempt
        continuation.resume(returning: attempt)
    }
}
