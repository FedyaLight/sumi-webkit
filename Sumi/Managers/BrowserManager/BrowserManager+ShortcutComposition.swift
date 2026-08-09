import Foundation

extension BrowserManager {
    func makeShortcutTargetResolver() -> BrowserShortcutTargetResolver {
        BrowserShortcutTargetResolver(
            windows: windowRegistry,
            pages: shellRuntime.activePageResolver
        )
    }

    func makeShortcutActionRouter() -> BrowserShortcutActionRouter {
        let shell = shellRuntime
        let urlBar = urlBarBundle
        let chrome = chromeBundle
        let history = historyBundle
        let sessions = windowSessionBundle
        return BrowserShortcutActionComposition.make(
            shell: shell,
            tabOpening: tabOpening,
            tabSelection: browserTabSelection,
            newTabCommit: urlBar.commandPaletteCommit,
            splitQuery: splitQuery,
            splitLayout: splitLayout,
            emptySplitCreation: splitEmptyCreation,
            spaces: spaceStateOwner,
            pins: shortcutPinCollectionStateOwner,
            favorite: favoriteShortcutPlacementOwner,
            regularTabShortcuts: sidebarRegularTabShortcutCommands,
            regularTabs: regularTabCollectionOwner,
            pinCommands: sidebarPinCommands,
            splitGroups: splitGroupStore,
            splitOrdering: splitGroupSidebarOrdering,
            splitMoves: sidebarDragRouter,
            spaceTransitions: windowSpaceTransitions,
            folderOpenState: folderOpenState,
            sessionPersistence: windowSessionPersistenceCoordinator,
            history: history.historyNavigationOwner,
            pageCommands: chrome.activePageCommands,
            pageActions: urlBar.contextOwner.pageActionOwner,
            boosts: optionalModules.boosts,
            zoom: chrome.zoomCommandOwner,
            privacyAndPopovers: chrome.commands,
            windowCommands: windowCommands,
            dialogs: chrome.nativeDialogPresentationOwner,
            sessionRecovery: sessions.sessionRecovery,
            tabClose: tabCloseOrchestration,
            theme: chrome.workspaceThemeEditorOwner,
            sidebar: chrome.sidebarPresentationOwner,
            folderActions: chrome.sidebarActionOwner,
            settings: urlBar.settingsNavigation,
            settingsAttachment: settingsAttachment,
            find: findManager,
            commandPalette: urlBar.commandPalettePresentation
        )
    }
}
