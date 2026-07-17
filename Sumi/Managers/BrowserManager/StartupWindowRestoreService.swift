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
    private let restoration: WindowSessionRestoreService
    private let windowReopen: any WindowSessionReopening
    private var pendingRestore: PendingRestore?

    var pendingRestoreTask: Task<Void, Never>? {
        pendingRestore?.task
    }

    init(
        startupRestore: any BrowserStartupSessionRestoreProviding,
        archive: LastSessionWindowArchive,
        openWindows: OpenWindowSessionCatalog,
        restoration: WindowSessionRestoreService,
        windowReopen: any WindowSessionReopening
    ) {
        self.startupRestore = startupRestore
        self.archive = archive
        self.openWindows = openWindows
        self.restoration = restoration
        self.windowReopen = windowReopen
    }

    isolated deinit {
        pendingRestore?.task.cancel()
    }

    func restoreIfNeeded() {
        guard pendingRestore == nil else { return }
        let sourceSnapshots = startupRestore.windowSnapshots
        guard sourceSnapshots.isEmpty == false else { return }
        let launchWindow = openWindows.deterministicRegularWindow()
        let immediateArchiveAttempt = archive.beginRestoreAttempt()

        let operationID = UUID()
        let startupRestore = startupRestore
        let archive = archive
        let openWindows = openWindows
        let restoration = restoration
        let windowReopen = windowReopen
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
                restoration: restoration,
                windowReopen: windowReopen
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
        restoration: WindowSessionRestoreService,
        windowReopen: any WindowSessionReopening
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
            startupWindowArchiveID: liveLaunchWindow?.restorationState.restoredSessionWindowID
        )

        if let liveLaunchWindow,
           let primarySnapshot = restorationPlan.primarySnapshotForStartupWindow {
            liveLaunchWindow.restorationState.restoredSessionWindowID = primarySnapshot.id
            guard restoration.applyWindowSessionSnapshot(
                primarySnapshot.session,
                to: liveLaunchWindow
            ) else {
                liveLaunchWindow.restorationState.restoredSessionWindowID = nil
                return false
            }
        }

        let refreshedWindowIDs = Set(
            openWindows.regularWindowSnapshots(excludingWindowID: nil).map(\.id)
        )
        let unresolvedSnapshots = restorationPlan.additionalSnapshots.filter {
            refreshedWindowIDs.contains($0.id) == false
        }
        for snapshot in unresolvedSnapshots {
            guard Task.isCancelled == false,
                  await windowReopen.reopenWindow(from: snapshot) else {
                return false
            }
        }
        return Task.isCancelled == false
    }
}
