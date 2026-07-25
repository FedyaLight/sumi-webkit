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
        let navigationTargetActivation =
            CommandPaletteNavigationTargetActivation(
                shortcuts: CommandPaletteShortcutActivation(
                    pins: shortcutPinCollectionStateOwner,
                    materializer: shortcutTabMaterializer,
                    selection: selection
                ),
                splitGroups: CommandPaletteSplitGroupActivation(
                    splitGroups: splitGroupStore,
                    splitFocus: splitShortcutFocus,
                    spaces: spaceStateOwner,
                    spaceTransitions: { [unowned self] in
                        self.windowSpaceTransitions
                    }
                )
            )
        let tabTargets = CommandPaletteTabTargetCommitter(
            splitPlaceholders: placeholders,
            selectTab: { [selection] tab, window in
                selection.selectTab(
                    tab,
                    in: window,
                    loadPolicy: .immediate
                )
            }
        )
        return CommandPaletteCommitService(
            presentation: presentation,
            destinations: CommandPaletteDestinationRouter(
                tabOpening: { [tabOpening] in tabOpening },
                tabTargets: tabTargets,
                pageNavigation: pageNavigation,
                activePageTab: { [activePages] window in
                    activePages.resolve(in: window)?.tab
                }
            ),
            tabTargets: tabTargets,
            tabForID: { [membership] id in
                membership.tab(for: id)
            },
            activateNavigationTarget: {
                [navigationTargetActivation] identity, window in
                navigationTargetActivation.activate(identity, in: window)
            }
        )
    }
}
