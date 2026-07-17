import Foundation

@MainActor
final class CleanStartupSessionArchiveTransaction {
    private let startupRestore: BrowserStartupSessionRestoreOwner
    private let persistence: TabStructuralPersistenceService
    private let openWindows: OpenWindowSessionCatalog

    init(
        startupRestore: BrowserStartupSessionRestoreOwner,
        persistence: TabStructuralPersistenceService,
        openWindows: OpenWindowSessionCatalog
    ) {
        self.startupRestore = startupRestore
        self.persistence = persistence
        self.openWindows = openWindows
    }

    func archiveLoadedSession() {
        startupRestore.archiveLoadedSessionForManualRestore(
            currentWindowSnapshots: { [openWindows] in
                openWindows.regularWindowSnapshots(excludingWindowID: nil)
            },
            currentTabSnapshot: { [persistence] in
                persistence.buildSnapshot()
            }
        )
    }

    func persistCleanState() {
        Task { @MainActor [weak persistence] in
            _ = await persistence?.persistFullReconcileAwaitingResult(
                reason: "startup clean policy"
            )
        }
    }
}
