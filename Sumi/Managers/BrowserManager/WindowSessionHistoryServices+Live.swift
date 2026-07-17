import Foundation

extension WindowSessionHistoryServices {
    /// Composes session history from stable, role-exact browser services.
    @MainActor
    static func live(
        browserManager: BrowserManager,
        snapshotFactory: WindowSessionSnapshotFactory,
        startupRestore: any BrowserStartupSessionRestoreProviding
    ) -> WindowSessionHistoryServices {
        let catalog = OpenWindowSessionCatalog(
            windows: browserManager.windowRegistry,
            snapshots: snapshotFactory
        )
        let archive = LastSessionWindowArchive(
            openWindows: catalog,
            lastSessionWindowsStore: browserManager.lastSessionWindowsStore,
            startupRestore: startupRestore
        )
        let recorder = ClosedWindowHistoryRecorder(
            snapshots: snapshotFactory,
            titles: ClosedWindowDisplayTitleProjection(
                windowTabs: browserManager.shellRuntime.windowTabs,
                spaces: browserManager.spaceStateOwner
            ),
            recentlyClosedManager: browserManager.recentlyClosedManager
        )
        return WindowSessionHistoryServices(
            catalog: catalog,
            archive: archive,
            recorder: recorder
        )
    }
}
