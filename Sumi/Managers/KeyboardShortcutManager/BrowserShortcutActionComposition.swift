import Foundation

/// Stateless composition boundary for keyboard shortcut routing. Every input
/// is an exact behaviorful role; no browser root or deferred service locator
/// crosses this boundary.
@MainActor
enum BrowserShortcutActionComposition {
    static func make(
        shell: BrowserShellRuntime,
        tabOpening: BrowserTabOpeningOwner,
        tabSelection: BrowserTabSelectionOwner,
        newTabCommit: FloatingBarCommitService,
        splitQuery: WindowSplitQuery,
        splitLayout: SplitLayoutService,
        splitInsertion: SplitInsertionService,
        emptySplitCreation: EmptySplitCreationWorkflow,
        spaces: TabSpaceCollectionStateOwner,
        spaceTransitions: BrowserWindowSpaceTransitionService,
        folderOpenState: TabFolderOpenStateService,
        sessionPersistence: WindowSessionPersistenceCoordinator,
        history: BrowserHistoryNavigationOwner,
        pageCommands: ActivePageCommandService,
        zoom: BrowserZoomCommandOwner,
        privacyAndPopovers: BrowserChromeCommands,
        windowCommands: BrowserWindowCommands,
        dialogs: BrowserNativeDialogPresentationOwner,
        sessionRecovery: BrowserSessionRecoveryCommands,
        tabClose: BrowserTabCloseOrchestrationOwner,
        theme: BrowserWorkspaceThemeEditorOwner,
        sidebar: BrowserSidebarPresentationOwner,
        find: FindManager,
        floatingBar: FloatingBarPresentationService
    ) -> BrowserShortcutActionRouter {
        let activePage = shell.activePageResolver
        let tabCommands = BrowserKeyboardTabSelectionCommands(
            windows: shell.windowRegistry,
            windowTabs: shell.windowTabs,
            opening: tabOpening,
            newTabCommit: newTabCommit,
            selection: tabSelection
        )
        let splitCommands = BrowserKeyboardSplitCommands(
            shell: shell,
            query: splitQuery,
            layout: splitLayout,
            insertion: splitInsertion,
            emptyCreation: emptySplitCreation
        )
        let spaceCommands = BrowserKeyboardSpaceCommands(
            shell: shell,
            spaces: spaces,
            transitions: spaceTransitions,
            folderOpenState: folderOpenState,
            persistence: sessionPersistence
        )
        let readerCommands = BrowserKeyboardReaderCommands(activePage: activePage)
        return BrowserShortcutActionRouter(
            page: BrowserShortcutPageCommandDispatcher(
                history: history,
                page: pageCommands,
                zoom: zoom,
                privacy: privacyAndPopovers
            ),
            tabs: BrowserShortcutTabCommandDispatcher(
                selection: tabCommands,
                splits: splitCommands,
                close: tabClose
            ),
            windowsAndSpaces: BrowserShortcutWindowSpaceCommandDispatcher(
                windows: windowCommands,
                dialogs: dialogs,
                recovery: sessionRecovery,
                spaces: spaceCommands
            ),
            chrome: BrowserShortcutChromeCommandDispatcher(
                chrome: privacyAndPopovers,
                theme: theme,
                sidebar: sidebar,
                reader: readerCommands
            ),
            overlays: BrowserShortcutOverlayCommandDispatcher(
                activePage: activePage,
                find: find,
                dialogs: dialogs,
                floatingBar: floatingBar
            )
        )
    }
}
