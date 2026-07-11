import Foundation

/// Restores the startup window archive as one retryable transaction.
///
/// The archive lease prevents ordinary activation and persistence callbacks
/// from replacing the retry source while new shell windows are registering.
/// A partial failure deliberately leaves both the startup offer and archive
/// untouched; a later attempt skips windows already restored by stable ID.
@MainActor
final class StartupWindowRestoreService {
    private struct PendingRestore {
        let id: UUID
        let task: Task<Void, Never>
    }

    private let startupRestore: any BrowserStartupSessionRestoreProviding
    private let archive: LastSessionWindowArchive
    private let openWindows: OpenWindowSessionCatalog
    private let startupWindow: @MainActor () -> BrowserWindowState?
    private let applySnapshot: @MainActor (
        LastSessionWindowSnapshot,
        BrowserWindowState
    ) -> Void
    private let reopenWindow: @MainActor (
        LastSessionWindowSnapshot
    ) async -> Bool
    private var pendingRestore: PendingRestore?

    var pendingRestoreTask: Task<Void, Never>? {
        pendingRestore?.task
    }

    init(
        startupRestore: any BrowserStartupSessionRestoreProviding,
        archive: LastSessionWindowArchive,
        openWindows: OpenWindowSessionCatalog,
        startupWindow: @escaping @MainActor () -> BrowserWindowState?,
        applySnapshot: @escaping @MainActor (
            LastSessionWindowSnapshot,
            BrowserWindowState
        ) -> Void,
        reopenWindow: @escaping @MainActor (
            LastSessionWindowSnapshot
        ) async -> Bool
    ) {
        self.startupRestore = startupRestore
        self.archive = archive
        self.openWindows = openWindows
        self.startupWindow = startupWindow
        self.applySnapshot = applySnapshot
        self.reopenWindow = reopenWindow
    }

    isolated deinit {
        pendingRestore?.task.cancel()
    }

    func restoreIfNeeded() {
        guard pendingRestore == nil else { return }
        let sourceSnapshots = startupRestore.windowSnapshots
        guard sourceSnapshots.isEmpty == false else { return }
        let launchWindow = startupWindow()
        let immediateArchiveAttempt = archive.beginRestoreAttempt()

        let operationID = UUID()
        let startupRestore = startupRestore
        let archive = archive
        let openWindows = openWindows
        let applySnapshot = applySnapshot
        let reopenWindow = reopenWindow
        let task = Task { @MainActor [weak self] in
            let archiveAttempt = if let immediateArchiveAttempt {
                immediateArchiveAttempt
            } else {
                await archive.acquireRestoreAttempt()
            }
            var outcome = LastSessionWindowArchive.RestoreAttemptOutcome.interrupted
            defer {
                archive.finishRestoreAttempt(archiveAttempt, outcome: outcome)
                if self?.pendingRestore?.id == operationID {
                    self?.pendingRestore = nil
                }
            }
            let didComplete = await Self.restore(
                sourceSnapshots: sourceSnapshots,
                openWindows: openWindows,
                launchWindow: launchWindow,
                applySnapshot: applySnapshot,
                reopenWindow: reopenWindow
            )
            if didComplete {
                startupRestore.markRestoreOfferConsumed()
                outcome = .completed
            }
        }
        pendingRestore = PendingRestore(id: operationID, task: task)
    }

    private static func restore(
        sourceSnapshots: [LastSessionWindowSnapshot],
        openWindows: OpenWindowSessionCatalog,
        launchWindow: BrowserWindowState?,
        applySnapshot: @MainActor (
            LastSessionWindowSnapshot,
            BrowserWindowState
        ) -> Void,
        reopenWindow: @MainActor (
            LastSessionWindowSnapshot
        ) async -> Bool
    ) async -> Bool {
        guard Task.isCancelled == false else { return false }

        let existingWindowIDs = Set(
            openWindows.regularWindowSnapshots(excludingWindowID: nil).map(\.id)
        )
        let liveLaunchWindow = launchWindow.flatMap {
            openWindows.containsRegularWindow($0) ? $0 : nil
        }
        let restorationPlan = StartupWindowRestorationPlanner.plan(
            archivedSnapshots: sourceSnapshots,
            existingWindowIDs: existingWindowIDs,
            hasStartupWindow: liveLaunchWindow != nil,
            startupWindowArchiveID: liveLaunchWindow?.restoredSessionWindowId
        )

        if let liveLaunchWindow,
           let primarySnapshot = restorationPlan.primarySnapshotForStartupWindow {
            liveLaunchWindow.restoredSessionWindowId = primarySnapshot.id
            applySnapshot(primarySnapshot, liveLaunchWindow)
        }

        let refreshedWindowIDs = Set(
            openWindows.regularWindowSnapshots(excludingWindowID: nil).map(\.id)
        )
        let unresolvedSnapshots = restorationPlan.additionalSnapshots.filter {
            refreshedWindowIDs.contains($0.id) == false
        }
        for snapshot in unresolvedSnapshots {
            guard Task.isCancelled == false,
                  await reopenWindow(snapshot) else {
                return false
            }
        }
        return Task.isCancelled == false
    }
}
