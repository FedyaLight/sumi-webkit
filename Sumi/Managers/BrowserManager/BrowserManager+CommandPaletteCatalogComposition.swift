import Foundation
import SumiDomain

/// Assembles the palette's SwiftUI context and the read-only catalogs it
/// searches over. These stay separate from the palette's browser-side service
/// composition: the catalogs are pure projections of browser collections,
/// injected as closures so tests can supply fixtures without building the live
/// browser graph.
@MainActor
extension BrowserManager {
    func composeCommandPaletteActiveTabSuggestions() -> ActiveTabSuggestionOwner {
        let membership = tabCollectionMembershipOwner
        let shortcutPresentation = shortcutPresentationOwner
        let runtimeConnection = runtimePortConnection
        return ActiveTabSuggestionOwner(
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
    }

    func composeCommandPaletteNavigationTargetCatalog(
        activeTabs: ActiveTabSuggestionOwner
    ) -> CommandPaletteNavigationTargetCatalog {
        let spaces = spaceStateOwner
        let regularTabs = regularTabCollectionOwner
        let pins = shortcutPinCollectionStateOwner
        let shortcutPresentation = shortcutPresentationOwner
        let splitGroups = splitGroupStore
        return CommandPaletteNavigationTargetCatalog(
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
    }

    func composeCommandPaletteBrowserContext(
        presentation: CommandPalettePresentationService,
        commit: CommandPaletteCommitService
    ) -> CommandPaletteBrowserContextFactory {
        let navigationTargets = composeCommandPaletteNavigationTargetCatalog(
            activeTabs: composeCommandPaletteActiveTabSuggestions()
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
            sessionCommands: CommandPaletteSessionCommands(
                presentation: presentation,
                commit: commit,
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
                }
            )
        )
    }
}
