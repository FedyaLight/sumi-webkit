import Foundation

@MainActor
extension BrowserManager {
    func composeFloatingBarPresentation()
        -> FloatingBarPresentationService {
        let windows = windowRegistry
        let windowTabs = shellRuntime.windowTabs
        let splitCancellation = emptySplitSession
        let themes = workspaceThemeEditorOwner
        let persistence = windowSessionPersistenceCoordinator
        return FloatingBarPresentationService(
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

    func composeFloatingBarServices(
        presentation: FloatingBarPresentationService
    ) -> FloatingBarServices {
        let settings = settingsState
        let webViews = webViewRoutingService
        let pageNavigation = FloatingBarPageNavigationService(
            settings: { [settings] in settings.settings },
            loadPage: { [webViews] url, tab, window in
                webViews.loadPage(
                    url,
                    for: tab,
                    in: window,
                    reason: "FloatingBar.currentPage"
                )
            }
        )
        let placeholders = splitEmptyPlaceholders
        let selection = browserTabSelection
        let activePages = shellRuntime.activePageResolver
        let tabOpening = tabOpening
        let commit = FloatingBarCommitService(
            presentation: presentation,
            tabOpening: { [tabOpening] in tabOpening },
            tabTargets: FloatingBarTabTargetCommitter(
                splitPlaceholders: placeholders,
                selectTab: { [selection] tab, window in
                    selection.selectTab(
                        tab,
                        in: window,
                        loadPolicy: .immediate
                    )
                }
            ),
            activePageTab: { [activePages] window in
                activePages.resolve(in: window)?.tab
            },
            pageNavigation: pageNavigation
        )

        let currentProfile = currentProfileAuthority
        let dataServices = dataServices
        let membership = tabCollectionMembershipOwner
        let shortcutPresentation = shortcutPresentationOwner
        let runtimeConnection = runtimePortConnection
        let history = historyManager
        let bookmarks = bookmarkManager
        let context = FloatingBarBrowserContextFactory(
            currentProfileId: { [currentProfile] in
                currentProfile.currentProfile?.id
            },
            faviconContext: { [currentProfile, dataServices] in
                FloatingBarFaviconContext(
                    partition: dataServices.faviconService.partition(
                        profile: currentProfile.currentProfile
                    ),
                    imageReader: dataServices.faviconCapabilities.images,
                    prefetch: dataServices.faviconCapabilities.prefetch
                )
            },
            configureSearchManager: {
                [membership, shortcutPresentation, runtimeConnection, history, bookmarks]
                searchManager in
                searchManager.setTabSources(
                    membership: membership,
                    shortcutPresentation: shortcutPresentation,
                    runtimeConnection: runtimeConnection
                )
                searchManager.setHistoryManager(history)
                searchManager.setBookmarkManager(bookmarks)
                searchManager.updateProfileContext()
            },
            deleteHistoryEntry: { [history] entry in
                await history.delete(
                    query: FloatingBarBrowserContextFactory
                        .historyDeletionQuery(for: entry)
                )
            },
            presentation: presentation,
            commit: commit
        )
        return FloatingBarServices(
            presentation: presentation,
            commit: commit,
            browserContext: context
        )
    }
}
