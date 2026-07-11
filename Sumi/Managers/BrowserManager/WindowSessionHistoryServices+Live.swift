import Foundation

extension WindowSessionHistoryServices {
    /// Composes the session-history services against the live browser graph.
    /// Composition seam only — the services themselves never see
    /// `BrowserManager`; they receive narrow closures and concrete
    /// collaborators captured here.
    @MainActor
    static func live(
        browserManager: BrowserManager,
        snapshotFactory: WindowSessionSnapshotFactory,
        startupRestore: any BrowserStartupSessionRestoreProviding
    ) -> WindowSessionHistoryServices {
        let catalog = OpenWindowSessionCatalog(
            allWindows: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            makeWindowSessionSnapshot: { windowState in
                snapshotFactory.make(for: windowState)
            }
        )
        let archive = LastSessionWindowArchive(
            openWindows: catalog,
            // The store is durable terminal state, not a live browser-kernel
            // capability. Close/termination persistence must remain usable
            // while BrowserManager is being released.
            lastSessionWindowsStore: { [weak browserManager, lastSessionWindowsStore = browserManager.lastSessionWindowsStore] in
                browserManager?.lastSessionWindowsStore ?? lastSessionWindowsStore
            },
            startupRestore: startupRestore
        )
        let recorder = ClosedWindowHistoryRecorder(
            openWindows: catalog,
            windowDisplayTitle: { [weak browserManager] windowState in
                guard let browserManager else { return "" }
                if let currentTab = browserManager.shellRuntime.windowTabs.currentTab(for: windowState) {
                    return currentTab.name
                }
                if let currentSpaceId = windowState.currentSpaceId,
                   let currentSpace = browserManager.tabManager.spaceStateOwner
                    .space(with: currentSpaceId) {
                    return currentSpace.name
                }
                return "Window"
            },
            // Closed-item history has the same terminal-safe lifetime as the
            // archive. Runtime title lookup above still requires the weak
            // browser kernel and degrades to an empty title during teardown.
            recentlyClosedManager: { [weak browserManager, recentlyClosedManager = browserManager.recentlyClosedManager] in
                browserManager?.recentlyClosedManager ?? recentlyClosedManager
            }
        )
        return WindowSessionHistoryServices(
            catalog: catalog,
            archive: archive,
            recorder: recorder
        )
    }
}
