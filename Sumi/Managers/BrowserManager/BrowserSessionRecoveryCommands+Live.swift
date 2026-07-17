extension BrowserSessionRecoveryCommands {
    @MainActor
    static func live(
        browserManager: BrowserManager,
        startupRestore: any BrowserStartupSessionRestoreProviding,
        sessionRestore: WindowSessionRestoreService,
        openWindows: OpenWindowSessionCatalog,
        archive: LastSessionWindowArchive,
        shortcutActivation: ShortcutPresentationActivationService,
        shortcutPinStore: ShortcutPinStoreOwner
    ) -> BrowserSessionRecoveryCommands {
        let windows = browserManager.windowRegistry
        let browserSelection = browserManager.browserTabSelection
        let windowReopen = WindowSessionReopenService(
            windows: windows,
            creation: ArchivedWindowCreationTransaction(
                windows: browserManager.windowCommands,
                restoration: sessionRestore
            )
        )
        let tabRestore = ClosedTabRestoreService(
            regularLifecycle: browserManager.regularTabLifecycleOwner,
            destinations: ClosedTabDestinationResolver(
                spaces: browserManager.spaceStateOwner,
                windows: windows
            ),
            publication: ClosedTabRestorePublication(
                activeSelection: browserManager.activeSelectionOwner,
                browserSelection: browserSelection
            )
        )
        let launcherRestore = ClosedShortcutLauncherRestoreTransaction(
            pins: browserManager.shortcutPinCollectionStateOwner,
            pinStore: shortcutPinStore,
            persistence: browserManager.structuralPersistence,
            destinations: ClosedShortcutLauncherDestinationResolver(
                folders: browserManager.folderCollectionStateOwner,
                runtimeConnection: browserManager.runtimePortConnection,
                spaces: browserManager.spaceStateOwner,
                profiles: browserManager.profileManager
            )
        )
        let shortcutRestore = ClosedShortcutRestoreService(
            liveInstances: ClosedShortcutLiveRestoreTransaction(
                pins: browserManager.shortcutPinCollectionStateOwner,
                activation: shortcutActivation,
                windows: ClosedShortcutWindowQuery(windows: windows),
                selection: browserSelection,
                launchers: launcherRestore
            ),
            launchers: launcherRestore
        )
        let itemReopen = RecentlyClosedItemReopenService(
            recentlyClosedItems: browserManager.recentlyClosedManager,
            startupRestore: startupRestore,
            tabRestore: tabRestore,
            shortcutRestore: shortcutRestore,
            windowReopen: windowReopen
        )
        let lastSessionRestore = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: openWindows,
            tabMerge: browserManager.lastSessionMergeMaterializer,
            windowReopen: windowReopen
        )
        return BrowserSessionRecoveryCommands(
            itemReopen: itemReopen,
            lastSessionRestore: lastSessionRestore,
            windowReopen: windowReopen
        )
    }
}
