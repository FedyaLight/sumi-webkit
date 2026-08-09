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
        newTabCommit: CommandPaletteCommitService,
        splitQuery: WindowSplitQuery,
        splitLayout: SplitLayoutService,
        emptySplitCreation: EmptySplitCreationWorkflow,
        spaces: TabSpaceCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        favorite: FavoriteShortcutPlacementOwner,
        regularTabShortcuts: SidebarRegularTabShortcutCommands,
        regularTabs: RegularTabCollectionOwner,
        pinCommands: SidebarPinCommands,
        splitGroups: SplitGroupStore,
        splitOrdering: SplitGroupSidebarOrderingService,
        splitMoves: SidebarDragOperationRouter,
        spaceTransitions: BrowserWindowSpaceTransitionService,
        folderOpenState: TabFolderOpenStateService,
        sessionPersistence: WindowSessionPersistenceCoordinator,
        history: BrowserHistoryNavigationOwner,
        pageCommands: ActivePageCommandService,
        pageActions: URLBarHubPageActionOwner,
        boosts: SumiBoostsModule,
        zoom: BrowserZoomCommandOwner,
        privacyAndPopovers: BrowserChromeCommands,
        windowCommands: BrowserWindowCommands,
        dialogs: BrowserNativeDialogPresentationOwner,
        sessionRecovery: BrowserSessionRecoveryCommands,
        tabClose: BrowserTabCloseOrchestrationOwner,
        theme: BrowserWorkspaceThemeEditorOwner,
        sidebar: BrowserSidebarPresentationOwner,
        folderActions: BrowserSidebarActionOwner,
        settings: BrowserSettingsNavigationService,
        settingsAttachment: BrowserSettingsAttachmentCoordinator,
        find: FindManager,
        commandPalette: CommandPalettePresentationService
    ) -> BrowserShortcutActionRouter {
        let tabCommands = BrowserKeyboardTabSelectionCommands(
            windowTabs: shell.windowTabs,
            opening: tabOpening,
            newTabCommit: newTabCommit,
            selection: tabSelection
        )
        let splitCommands = BrowserKeyboardSplitCommands(
            query: splitQuery,
            layout: splitLayout,
            emptyCreation: emptySplitCreation
        )
        let pinningCommands = BrowserKeyboardPinCommands(
            spaces: spaces,
            pins: pins,
            favorite: favorite,
            regularTabs: regularTabShortcuts,
            tabCollection: regularTabs,
            pinCommands: pinCommands,
            splitGroups: splitGroups,
            splitOrdering: splitOrdering,
            splitMoves: splitMoves
        )
        let spaceCommands = BrowserKeyboardSpaceCommands(
            spaces: spaces,
            transitions: spaceTransitions,
            folderOpenState: folderOpenState,
            persistence: sessionPersistence
        )
        let readerCommands = BrowserKeyboardReaderCommands()
        return BrowserShortcutActionRouter(
            page: BrowserShortcutPageCommandDispatcher(
                history: history,
                page: pageCommands,
                artifacts: BrowserShortcutPageArtifactCommands(
                    pageActions: pageActions,
                    boosts: boosts
                ),
                zoom: zoom,
                privacy: privacyAndPopovers
            ),
            tabs: BrowserShortcutTabCommandDispatcher(
                selection: tabCommands,
                splits: splitCommands,
                pins: pinningCommands,
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
                sidebar: BrowserShortcutSidebarCommands(
                    presentation: sidebar,
                    actions: folderActions
                ),
                reader: readerCommands,
                settings: BrowserShortcutSettingsCommands(
                    navigation: settings,
                    attachment: settingsAttachment
                )
            ),
            overlays: BrowserShortcutOverlayCommandDispatcher(
                find: find,
                dialogs: dialogs,
                commandPalette: commandPalette
            )
        )
    }
}
