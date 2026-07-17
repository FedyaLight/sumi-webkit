import Foundation

/// Creates a browser shell only after its archived session has been prepared
/// by the window-session restore transaction.
@MainActor
final class ArchivedWindowCreationTransaction {
    private let windows: BrowserWindowCommands
    private let restoration: WindowSessionRestoreService

    init(
        windows: BrowserWindowCommands,
        restoration: WindowSessionRestoreService
    ) {
        self.windows = windows
        self.restoration = restoration
    }

    func create(from snapshot: LastSessionWindowSnapshot) -> BrowserWindowState? {
        windows.createArchivedWindow(
            from: snapshot,
            sessionRestore: restoration
        )
    }
}
