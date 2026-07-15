import Foundation

extension BrowserURLBarBundle {
    static func makeFloatingBarServices(
        browserManager: BrowserManager,
        activePageResolver: ActivePageResolver
    ) -> FloatingBarServices {
        let emptySplitPlaceholders = browserManager.splitComposition
            .emptyPlaceholders
        let presentation = FloatingBarPresentationService(
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            hasValidCurrentSelection: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs
                    .hasValidCurrentSelection(in: windowState) ?? false
            },
            splitPlaceholders: {
                [weak emptySplitPlaceholders] in emptySplitPlaceholders
            },
            dismissThemePickerDiscardingIfNeeded: { [weak browserManager] in
                browserManager?.chromeBundle.workspaceThemeEditorOwner
                    .dismissThemePickerDiscardingIfNeeded()
            },
            persistence: { [weak browserManager] in
                browserManager?.windowSessionBundle.persistence
            }
        )
        let pageNavigation = FloatingBarPageNavigationService(
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            },
            loadPage: { [weak browserManager] url, tab, windowState in
                browserManager?.webViewRoutingService.loadPage(
                    url,
                    for: tab,
                    in: windowState,
                    reason: "FloatingBar.currentPage"
                )
            }
        )
        let commit = FloatingBarCommitService(
            presentation: presentation,
            tabOpening: { [weak tabOpening = browserManager.tabLifecycleService.opening] in
                tabOpening
            },
            tabTargets: FloatingBarTabTargetCommitter(
                splitPlaceholders: {
                    [weak emptySplitPlaceholders] in emptySplitPlaceholders
                },
                selectTab: { [weak browserManager] tab, windowState in
                    browserManager?.selectTab(tab, in: windowState) ?? .rejected
                }
            ),
            activePageTab: { [activePageResolver] windowState in
                activePageResolver.resolve(in: windowState)?.tab
            },
            pageNavigation: pageNavigation
        )
        let browserContext = makeFloatingBarBrowserContext(
            browserManager: browserManager,
            presentation: presentation,
            commit: commit
        )
        return FloatingBarServices(
            presentation: presentation,
            commit: commit,
            browserContext: browserContext
        )
    }

    private static func makeFloatingBarBrowserContext(
        browserManager: BrowserManager,
        presentation: FloatingBarPresentationService,
        commit: FloatingBarCommitService
    ) -> FloatingBarBrowserContextFactory {
        let dataServices = browserManager.dataServices
        let currentProfileAuthority = browserManager.currentProfileAuthority
        return FloatingBarBrowserContextFactory(
            currentProfileId: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile?.id
            },
            faviconContext: { [currentProfileAuthority] in
                FloatingBarFaviconContext(
                    partition: dataServices.faviconService.partition(
                        profile: currentProfileAuthority.currentProfile
                    ),
                    imageReader: dataServices.faviconCapabilities.images,
                    prefetch: dataServices.faviconCapabilities.prefetch
                )
            },
            configureSearchManager: { [weak browserManager] searchManager in
                guard let browserManager else { return }
                searchManager.setTabManager(browserManager.tabManager)
                searchManager.setHistoryManager(browserManager.historyManager)
                searchManager.setBookmarkManager(browserManager.bookmarkManager)
                searchManager.updateProfileContext()
            },
            deleteHistoryEntry: { [weak browserManager] entry in
                guard let browserManager else { return }
                await browserManager.historyManager.delete(
                    query: FloatingBarBrowserContextFactory
                        .historyDeletionQuery(for: entry)
                )
            },
            presentation: presentation,
            commit: commit
        )
    }
}
