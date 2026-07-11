extension BrowserSessionRecoveryCommands {
    /// Composes the session-recovery services against the live browser graph.
    /// Composition seam only — the services themselves never see
    /// `BrowserManager`; they receive narrow closures and concrete
    /// collaborators captured here.
    @MainActor
    static func live(
        browserManager: BrowserManager,
        startupRestore: any BrowserStartupSessionRestoreProviding,
        sessionRestore: WindowSessionRestoreService,
        openWindows: OpenWindowSessionCatalog,
        archive: LastSessionWindowArchive
    ) -> BrowserSessionRecoveryCommands {
        let windowReopen = WindowSessionReopenService(
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            createRestoredWindow: { [weak browserManager, weak sessionRestore] snapshot in
                guard let browserManager, let sessionRestore else { return nil }
                return browserManager.windowCommands.createPreparedWindow(
                    initialize: { windowState in
                        sessionRestore.prepareArchivedWindow(
                            snapshot,
                            forRegistration: windowState
                        )
                    },
                    discardPreparedState: {
                        sessionRestore.cancelPreparedWindowRegistration($0)
                    }
                )
            }
        )
        let tabRestore = ClosedTabRestoreService(
            tabManager: { [weak browserManager] in browserManager?.tabManager },
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            selectRestoredTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            }
        )
        let shortcutRestore = ClosedShortcutRestoreService(
            tabManager: { [weak browserManager] in
                browserManager?.tabManager
            },
            profileManager: { [weak browserManager] in
                browserManager?.profileManager
            },
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            selectRestoredTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            }
        )
        let itemReopen = RecentlyClosedItemReopenService(
            // Durable history keeps failed late reopen items intact.
            recentlyClosedItems: { [weak browserManager, recentlyClosedManager = browserManager.recentlyClosedManager] in
                browserManager?.recentlyClosedManager ?? recentlyClosedManager
            },
            startupRestore: startupRestore,
            tabRestore: tabRestore,
            shortcutRestore: shortcutRestore,
            windowReopen: windowReopen
        )
        let lastSessionRestore = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: openWindows,
            mergeLastSessionTabSnapshot: { [weak browserManager] snapshot in
                browserManager?.tabManager.lastSessionMergeMaterializer
                    .merge(snapshot)
            },
            windowReopen: windowReopen
        )
        return BrowserSessionRecoveryCommands(
            itemReopen: itemReopen,
            lastSessionRestore: lastSessionRestore,
            windowReopen: windowReopen
        )
    }
}
