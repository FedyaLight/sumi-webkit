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
            newTabCommit: urlBar.commandPalette.commit,
            splitQuery: splitQuery,
            splitLayout: splitLayout,
            emptySplitCreation: splitEmptyCreation,
            spaces: spaceStateOwner,
            spaceTransitions: windowSpaceTransitions,
            folderOpenState: folderOpenState,
            sessionPersistence: windowSessionPersistenceCoordinator,
            history: history.historyNavigationOwner,
            pageCommands: chrome.activePageCommands,
            zoom: chrome.zoomCommandOwner,
            privacyAndPopovers: chrome.commands,
            windowCommands: windowCommands,
            dialogs: chrome.nativeDialogPresentationOwner,
            sessionRecovery: sessions.sessionRecovery,
            tabClose: tabCloseOrchestration,
            theme: chrome.workspaceThemeEditorOwner,
            sidebar: chrome.sidebarPresentationOwner,
            find: findManager,
            commandPalette: urlBar.commandPalette.presentation
        )
    }
}
