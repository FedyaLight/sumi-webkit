import SumiDomain

@MainActor
struct SidebarBrowserContext {
    let profileManager: ProfileManager
    let liveFolderManager: SumiLiveFolderManager
    let splitQuery: WindowSplitQuery
    let splitLayout: SplitLayoutService
    let splitInsertion: SplitInsertionService
    let splitMembership: SplitGroupMembershipQuery
    let emptySplitCreation: EmptySplitCreationWorkflow
    let downloadManager: DownloadManager
    let downloadsPopoverPresenter: DownloadsPopoverPresenter
    let glanceManager: GlanceManager
    let extensionSurfaceStore: BrowserExtensionSurfaceStore
    let faviconImageReader: any BrowserFaviconImageReading
    let favoriteBackdropReader: any BrowserFavoriteBackdropReading
    let spaceEditorPresentation: SidebarSpaceEditorPresentationService
    let folderEditorPresentation: SidebarFolderEditorPresentationService
    let shortcutEditorPresentation: SidebarShortcutEditorPresentationService
    let workspaceThemeEditor: BrowserWorkspaceThemeEditorOwner
    let spaceDeletionPresentation: SidebarSpaceDeletionPresentationOwner
    let sharingPresentation: BrowserNativeDialogPresentationOwner
    let spaceTransitions: BrowserSpaceTransitionRoutingOwner
    let settingsNavigation: BrowserSettingsNavigationService
    let folderActions: BrowserSidebarActionOwner
    let tabSelection: BrowserTabSelectionOwner
    let tabClose: BrowserTabCloseOrchestrationOwner
    let regularTabs: RegularTabCollectionOwner
    let tabOpening: BrowserTabOpeningOwner
    let commandPaletteCommit: CommandPaletteCommitService
    let splitFocusCommands: SidebarSplitFocusCommands
    let splitCloseCommand: SidebarSplitCloseCommand
    let splitGroupLifecycle: SidebarSplitGroupLifecycleCommands
    let splitGroupEditor: SidebarSplitGroupEditorPresentationService
    let shortcutCopy: SidebarPinCommands
    let shortcutPinUnload: BrowserShortcutPinUnloadOwner
    let headerContextOwner: BrowserURLBarContextOwner
    let profileAuthority: BrowserCurrentProfileAuthority
    let extensionToolbarActions: SumiExtensionToolbarActionSurface
    let extensionsModule: SumiExtensionsModule
    let extensionActionTabs: SidebarExtensionActionTabQuery
    let extensionSettingsNavigation: BrowserSettingsNavigationService
    let sidebarPresentation: BrowserSidebarPresentationOwner
    let mediaStoreConfiguration: SidebarMediaStoreConfigurationOwner
    let windows: SidebarWindowIdentityQuery
}
