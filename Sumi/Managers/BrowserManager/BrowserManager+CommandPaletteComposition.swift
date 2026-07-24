import Foundation
import SumiDomain

@MainActor
extension BrowserManager {
    func composeCommandPalettePresentation()
        -> CommandPalettePresentationService {
        let windows = windowRegistry
        let windowTabs = shellRuntime.windowTabs
        let splitCancellation = emptySplitSession
        let themes = workspaceThemeEditorOwner
        let persistence = windowSessionPersistenceCoordinator
        return CommandPalettePresentationService(
            windowRegistry: { [windows] in windows },
            hasValidCurrentSelection: { [windowTabs] window in
                windowTabs.hasValidCurrentSelection(in: window)
            },
            splitCancellation: splitCancellation,
            dismissThemePickerDiscardingIfNeeded: { [themes] in
                themes.dismissThemePickerDiscardingIfNeeded()
            },
            persistence: { [persistence] in persistence }
        )
    }

    func composeCommandPaletteCommit(
        presentation: CommandPalettePresentationService
    ) -> CommandPaletteCommitService {
        let settings = settingsState
        let webViews = webViewRoutingService
        let pageNavigation = CommandPalettePageNavigationService(
            settings: { [settings] in settings.settings },
            loadPage: { [webViews] url, tab, window in
                webViews.loadPage(
                    url,
                    for: tab,
                    in: window,
                    reason: "CommandPalette.currentPage"
                )
            }
        )
        let placeholders = splitEmptyPlaceholders
        let selection = browserTabSelection
        let activePages = shellRuntime.activePageResolver
        let membership = tabCollectionMembershipOwner
        let tabOpening = tabOpening
        let spaces = spaceStateOwner
        let pins = shortcutPinCollectionStateOwner
        let splitGroups = splitGroupStore
        let shortcutMaterializer = shortcutTabMaterializer
        let splitFocus = splitShortcutFocus
        let transitionToSpace: @MainActor (
            Space,
            BrowserWindowState
        ) -> Bool = { [weak self] space, window in
            guard let self else { return false }
            self.windowSpaceTransitions.setActiveSpace(space, in: window)
            return true
        }
        return CommandPaletteCommitService(
            presentation: presentation,
            tabOpening: { [tabOpening] in tabOpening },
            tabTargets: CommandPaletteTabTargetCommitter(
                splitPlaceholders: placeholders,
                selectTab: { [selection] tab, window in
                    selection.selectTab(
                        tab,
                        in: window,
                        loadPolicy: .immediate
                    )
                }
            ),
            tabForID: { [membership] id in
                membership.tab(for: id)
            },
            activePageTab: { [activePages] window in
                activePages.resolve(in: window)?.tab
            },
            pageNavigation: pageNavigation,
            activateNavigationTarget: {
                [pins, shortcutMaterializer, selection, splitGroups,
                 splitFocus, spaces, transitionToSpace]
                identity,
                window in
                switch identity {
                case .shortcut(let pinID):
                    guard let pin = pins.shortcutPin(by: pinID),
                          let tab = shortcutMaterializer.materialize(
                              pin,
                              in: window.id,
                              currentSpaceId:
                                  pin.spaceId ?? window.currentSpaceId
                          )
                    else { return false }
                    return selection.selectTab(
                        tab,
                        in: window,
                        loadPolicy: .immediate
                    ).wasCommitted

                case .splitGroup(let groupID):
                    guard let group = splitGroups.group(id: groupID)
                    else { return false }
                    if let spaceID = group.container.spaceId,
                       spaceID != window.currentSpaceId {
                        guard let space = spaces.space(with: spaceID),
                              splitFocus.activateSplitGroup(group, in: window)
                        else { return false }
                        return transitionToSpace(space, window)
                    }
                    return splitFocus.activateSplitGroup(group, in: window)
                }
            }
        )
    }

    func composeCommandPaletteBrowserContext(
        presentation: CommandPalettePresentationService,
        commit: CommandPaletteCommitService
    ) -> CommandPaletteBrowserContextFactory {
        let spaces = spaceStateOwner
        let regularTabs = regularTabCollectionOwner
        let pins = shortcutPinCollectionStateOwner
        let membership = tabCollectionMembershipOwner
        let shortcutPresentation = shortcutPresentationOwner
        let runtimeConnection = runtimePortConnection
        let splitGroups = splitGroupStore
        let activeTabs = ActiveTabSuggestionOwner(
            allTabsForCurrentProfile: { [membership] in
                membership.allTabsForCurrentProfile()
            },
            liveShortcutTabs: { [shortcutPresentation] windowID in
                shortcutPresentation.liveShortcutTabs(in: windowID)
            },
            shortcutLiveTab: { [shortcutPresentation] pinID, windowID in
                shortcutPresentation.shortcutLiveTab(
                    for: pinID,
                    in: windowID
                )
            },
            visibleSplitTabIds: { [runtimeConnection] windowID in
                Set(
                    runtimeConnection.current?
                        .visibleSplitTabIds(for: windowID) ?? []
                )
            }
        )
        let navigationTargets = CommandPaletteNavigationTargetCatalog(
            spaces: { [spaces] in spaces.spaces },
            regularTabs: { [regularTabs, spaces] in
                regularTabs.allTabs(in: spaces.spaces)
            },
            essentialPins: { [pins] profileID in
                pins.essentialPins(for: profileID)
            },
            spacePinnedPins: { [pins] spaceID in
                pins.spacePinnedPins(for: spaceID)
            },
            splitGroups: { [splitGroups] in splitGroups.groups },
            liveShortcutTab: { [shortcutPresentation] pinID, windowID in
                shortcutPresentation.shortcutLiveTab(
                    for: pinID,
                    in: windowID
                )
            },
            activeTabs: { [activeTabs] window in
                activeTabs.tabs(for: window)
            }
        )
        let currentProfile = currentProfileAuthority
        let dataServices = dataServices
        let history = historyManager
        let bookmarks = bookmarkManager
        return CommandPaletteBrowserContextFactory(
            currentProfileId: { [currentProfile] in
                currentProfile.currentProfile?.id
            },
            faviconContext: { [currentProfile, dataServices] in
                CommandPaletteFaviconContext(
                    partition: dataServices.faviconService.partition(
                        profile: currentProfile.currentProfile
                    ),
                    imageReader: dataServices.faviconCapabilities.images,
                    prefetch: dataServices.faviconCapabilities.prefetch
                )
            },
            spaces: CommandPaletteSpaceCatalog(spaces: spaceStateOwner),
            extensions: CommandPaletteExtensionCatalog(
                module: optionalModules.extensions,
                tabs: SidebarExtensionActionTabQuery(
                    windowTabs: shellRuntime.windowTabs,
                    membership: tabCollectionMembershipOwner,
                    selection: shellRuntime.windowSelection,
                    tabStore: runtimeStore
                )
            ),
            makeSearchSession: {
                [history, bookmarks, navigationTargets]
                in
                let searchManager = SearchManager()
                searchManager.setHistoryManager(history)
                searchManager.setBookmarkManager(bookmarks)
                searchManager.setNavigationTargetCatalog(navigationTargets)
                return CommandPaletteSearchSessionOwner(
                    searchManager: searchManager
                )
            },
            deleteHistory: { [history] query in
                await history.delete(query: query)
            },
            presentation: presentation,
            commit: commit
        )
    }
}
