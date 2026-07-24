import Foundation

@MainActor
extension BrowserManager {
    func composeSidebarBrowserContext(
        spaceLifecycle: SidebarSpaceLifecycle
    ) -> SidebarBrowserContext {
        let profileAuthority = currentProfileAuthority
        let extensions = optionalModules.extensions
        let themeEditor = chromeBundle.workspaceThemeEditorOwner
        let dialogs = chromeBundle.nativeDialogPresentationOwner
        let sidebarPresentation = chromeBundle.sidebarPresentationOwner
        let headerContextOwner = urlBarBundle.contextOwner
        let shell = shellRuntime
        let mediaContext = composeSidebarMediaRuntimeContext()
        let windowIdentity = SidebarWindowIdentityQuery(
            registry: shell.windowRegistry
        )

        return SidebarBrowserContext(
            profileManager: profileManager,
            liveFolderManager: liveFolderManager,
            splitQuery: splitQuery,
            splitLayout: splitLayout,
            splitInsertion: splitInsertion,
            splitMembership: splitGroupMembership,
            emptySplitCreation: splitEmptyCreation,
            downloadManager: downloadManager,
            downloadsPopoverPresenter: chromeBundle.commands.downloadsPopoverPresenter,
            glanceManager: glanceManager,
            extensionSurfaceStore: extensions.surfaceStore,
            faviconImageReader: dataServices.faviconCapabilities.images,
            essentialBackdropReader:
                dataServices.faviconCapabilities.essentialBackdrops,
            spaceEditorPresentation: composeSidebarSpaceEditorPresentation(),
            folderEditorPresentation: composeSidebarFolderEditorPresentation(),
            shortcutEditorPresentation: composeSidebarShortcutEditorPresentation(),
            workspaceThemeEditor: themeEditor,
            spaceDeletionPresentation: SidebarSpaceDeletionPresentationOwner(
                lifecycle: spaceLifecycle,
                windows: windowIdentity,
                settings: settingsAttachment
            ),
            sharingPresentation: dialogs,
            spaceTransitions: composeSidebarSpaceTransitionRoutingOwner(),
            settingsNavigation: urlBarBundle.settingsNavigation,
            folderActions: chromeBundle.sidebarActionOwner,
            tabSelection: browserTabSelection,
            tabClose: tabCloseOrchestration,
            regularTabs: regularTabCollectionOwner,
            tabOpening: tabOpening,
            commandPaletteCommit: urlBarBundle.commandPaletteCommit,
            splitFocusCommands: SidebarSplitFocusCommands(
                focus: splitShortcutFocus,
                groups: splitGroupStore,
                windows: windowIdentity
            ),
            splitCloseCommand: SidebarSplitCloseCommand(
                groups: splitGroupStore,
                windows: windowIdentity,
                membership: tabCollectionMembershipOwner,
                shortcuts: shortcutPresentationOwner,
                close: tabCloseOrchestration
            ),
            splitGroupLifecycle: SidebarSplitGroupLifecycleCommands(
                groups: splitGroupStore,
                pins: shortcutPinCollectionStateOwner,
                pinCommands: sidebarPinCommands,
                hostedUnload: splitShortcutHostedUnload,
                membership: tabCollectionMembershipOwner,
                close: tabCloseOrchestration,
                notifications: notificationPresenter
            ),
            splitGroupEditor: SidebarSplitGroupEditorPresentationService(
                groups: splitGroupStore,
                mutations: splitGroupMutations,
                windows: windowIdentity,
                duplication: SidebarSplitGroupDuplicationService(
                    regular: RegularSplitGroupDuplicationService(
                        groups: splitGroupStore,
                        mutations: splitGroupMutations,
                        regularTabs: regularTabCollectionOwner,
                        duplication: SplitTabDuplicationService(
                            spaces: spaceStateOwner,
                            regularTabs: regularTabLifecycleOwner,
                            closure: tabClosureService
                        )
                    ),
                    saved: SavedSplitGroupDuplicationService(
                        groups: splitGroupStore,
                        mutations: splitGroupMutations,
                        pins: shortcutPinCollectionStateOwner,
                        pinStore: shortcutPinStoreOwner
                    )
                ),
                moves: SidebarSplitGroupMoveService(
                    ordering: splitGroupSidebarOrdering,
                    conversion: splitGroupContainerConversion,
                    folders: folderCollectionStateOwner,
                    regularTabs: regularTabCollectionOwner,
                    liveFolders: liveFolderManager
                )
            ),
            shortcutCopy: sidebarPinCommands,
            shortcutPinUnload: composeSidebarShortcutPinUnloadOwner(),
            headerContextOwner: headerContextOwner,
            profileAuthority: profileAuthority,
            extensionToolbarActions: extensions.toolbarActions,
            extensionsModule: extensions,
            extensionActionTabs: SidebarExtensionActionTabQuery(
                windowTabs: shell.windowTabs,
                membership: tabCollectionMembershipOwner,
                selection: shell.windowSelection,
                tabStore: runtimeStore
            ),
            extensionSettingsNavigation: urlBarBundle.settingsNavigation,
            sidebarPresentation: sidebarPresentation,
            mediaStoreConfiguration: SidebarMediaStoreConfigurationOwner(
                context: mediaContext
            ),
            windows: windowIdentity
        )
    }

    func composeSidebarHoverRuntime() -> HoverSidebarRuntime {
        let runtimeConnection = runtimePortConnection
        return HoverSidebarRuntime(
            browserRuntimeAvailable: { [runtimeConnection] in
                runtimeConnection.current != nil
            },
            settings: { [weak self] in self?.sumiSettings }
        )
    }

    private func composeSidebarMediaRuntimeContext()
        -> SumiNativeNowPlayingRuntimeContext {
        let shell = shellRuntime
        let membership = tabCollectionMembershipOwner
        let webViewRouting = webViewRoutingService
        let selection = browserTabSelection

        return SumiNativeNowPlayingRuntimeContext.live(
            runtime: SumiNativeNowPlayingBrowserRuntime(
                windowStates: { [windowRegistry] in
                    Array(windowRegistry.windows.values)
                },
                windowState: { [windowRegistry] windowID in
                    windowRegistry.windows[windowID]
                },
                windowRegistry: { [windowRegistry] in windowRegistry },
                currentTab: { [shell] windowState in
                    shell.windowTabs.currentTab(for: windowState)
                },
                mediaCandidateTabs: { [shell] windowState in
                    shell.windowTabs.windowScopedMediaCandidateTabs(in: windowState)
                },
                tab: { [membership] tabID in membership.tab(for: tabID) },
                resolvedNowPlayingWebView: { [webViewRouting] tab, windowState in
                    webViewRouting.windowOwnedWebView(for: tab, in: windowState.id)
                },
                selectTab: { [selection] tab, windowState in
                    _ = selection.selectTab(
                        tab,
                        in: windowState,
                        loadPolicy: .immediate
                    )
                }
            )
        )
    }
}
