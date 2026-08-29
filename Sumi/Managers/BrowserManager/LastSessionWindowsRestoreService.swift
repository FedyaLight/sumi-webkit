import Foundation

/// Reopens every window of the previous session that is not already open:
/// picks the startup archive or the persisted last-session archive as the
/// source, merges the archived tab snapshot exactly once per command,
/// reopens the missing windows sequentially, and refreshes the archive only
/// after every window restored — a failed or partial batch keeps the archive
/// available for retry.
@MainActor
final class LastSessionWindowsRestoreService {
    private let startupRestore: any BrowserStartupSessionRestoreProviding
    private let archive: LastSessionWindowArchive
    private let openWindows: OpenWindowSessionCatalog
    private let tabMerge: TabLastSessionMergeMaterializer
    private let windowReopen: any WindowSessionReopening

    /// Restore-in-flight handle; exposed so callers/tests can await the
    /// asynchronous window reopening explicitly.
    private(set) var pendingRestoreTask: Task<Void, Never>?

    isolated deinit {
        pendingRestoreTask?.cancel()
    }

    init(
        startupRestore: any BrowserStartupSessionRestoreProviding,
        archive: LastSessionWindowArchive,
        openWindows: OpenWindowSessionCatalog,
        tabMerge: TabLastSessionMergeMaterializer,
        windowReopen: any WindowSessionReopening
    ) {
        self.startupRestore = startupRestore
        self.archive = archive
        self.openWindows = openWindows
        self.tabMerge = tabMerge
        self.windowReopen = windowReopen
    }

    var canOfferStartupSessionRestoreShortcut: Bool {
        startupRestore.canOfferRestoreShortcut
            && missingSnapshots(in: startupRestore.windowSnapshots).isEmpty == false
    }

    var canRestoreAnyLastSession: Bool {
        let sourceSnapshots = startupRestore.canOfferRestoreShortcut
            ? startupRestore.windowSnapshots
            : archive.archivedWindowSnapshots
        return missingSnapshots(in: sourceSnapshots).isEmpty == false
    }

    func reopenAllWindowsFromLastSession() {
        guard pendingRestoreTask == nil else { return }
        let startupRestore = startupRestore
        let useStartupArchive = startupRestore.canOfferRestoreShortcut
        let sourceSnapshots = useStartupArchive
            ? startupRestore.windowSnapshots
            : archive.archivedWindowSnapshots
        let sourceTabSnapshot = useStartupArchive
            ? (startupRestore.tabSnapshot ?? archive.archivedTabSnapshot)
            : archive.archivedTabSnapshot
        let snapshotsToRestore = missingSnapshots(in: sourceSnapshots)
        guard snapshotsToRestore.isEmpty == false else {
            guard sourceSnapshots.isEmpty == false else { return }
            if useStartupArchive {
                startupRestore.markRestoreOfferConsumed()
            }
            archive.refresh(persistence: .enqueued)
            return
        }
        guard let restoreAttempt = archive.beginRestoreAttempt() else { return }

        pendingRestoreTask = Task { @MainActor [windowReopen, tabMerge, archive, weak self] in
            var outcome = LastSessionWindowArchive.RestoreAttemptOutcome.interrupted
            defer {
                archive.finishRestoreAttempt(restoreAttempt, outcome: outcome)
                self?.pendingRestoreTask = nil
            }
            if let sourceTabSnapshot {
                guard tabMerge.merge(sourceTabSnapshot) else {
                    return
                }
            }
            var restoredEveryWindow = true
            for snapshot in snapshotsToRestore {
                guard Task.isCancelled == false else { return }
                if await windowReopen.reopenWindow(from: snapshot) == false {
                    restoredEveryWindow = false
                }
            }
            guard Task.isCancelled == false, restoredEveryWindow else {
                return
            }
            if useStartupArchive {
                startupRestore.markRestoreOfferConsumed()
            }
            outcome = .completed
        }
    }

    private func missingSnapshots(
        in sourceSnapshots: [LastSessionWindowSnapshot]
    ) -> [LastSessionWindowSnapshot] {
        let existingWindowIDs = openWindows.regularWindowIDs()
        return sourceSnapshots.filter { existingWindowIDs.contains($0.id) == false }
    }
}
