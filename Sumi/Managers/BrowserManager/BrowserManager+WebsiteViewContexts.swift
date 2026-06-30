import Combine
import SwiftUI

@MainActor
extension BrowserManager {
    func websiteViewBrowserContext(
        sidebarDragState: SidebarDragState
    ) -> WebsiteViewBrowserContext {
        WebsiteViewBrowserContext(
            currentTab: { [weak self] windowState in
                self?.currentTab(for: windowState)
            },
            workspaceTheme: { [weak self] spaceId in
                self?.space(for: spaceId)?.workspaceTheme
            },
            makeWebContentContext: {
                BrowserManagerWindowWebContentContext(
                    browserManager: self,
                    sidebarDragState: sidebarDragState
                )
            }
        )
    }

    var websiteNativeSurfaceRootBuilders: WebsiteNativeSurfaceRootBuilders {
        WebsiteNativeSurfaceRootBuilders(
            history: { [weak self] windowState in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    SumiHistoryTabRootView(
                        browserContext: historyPageBrowserContext,
                        windowState: windowState
                    )
                )
            },
            bookmarks: { [weak self] windowState in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    SumiBookmarksTabRootView(
                        browserContext: bookmarksPageBrowserContext,
                        windowState: windowState
                    )
                )
            },
            settings: { [weak self] windowState in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    SumiSettingsTabRootView(
                        browserManager: self,
                        windowState: windowState
                    )
                    .environmentObject(self.extensionSurfaceStore)
                )
            }
        )
    }

    var historyPageBrowserContext: HistoryPageBrowserContext {
        HistoryPageBrowserContext(
            historyManager: historyManager,
            faviconService: dataServices.faviconService,
            currentProfile: { [weak self] in
                self?.currentProfile
            },
            currentProfileUpdates: $currentProfile.eraseToAnyPublisher(),
            nativeModalPresentationUpdates: $nativeModalPresentation
                .map { _ in () }
                .eraseToAnyPublisher(),
            isNativeModalPresented: { [weak self] windowId in
                guard let windowId else { return false }
                return self?.isNativeModalPresented(in: windowId) ?? false
            },
            currentTab: { [weak self] windowState in
                self?.currentTab(for: windowState)
            },
            openHistoryURL: { [weak self] url, windowState, preferredOpenMode in
                self?.openHistoryURL(
                    url,
                    in: windowState,
                    preferredOpenMode: preferredOpenMode
                )
            },
            openHistoryURLsInNewTabs: { [weak self] urls, windowState in
                self?.openHistoryURLsInNewTabs(urls, in: windowState)
            },
            presentBrowsingDataSheet: { [weak self] windowState in
                self?.presentBrowsingDataSheet(windowState: windowState)
            },
            scheduleRuntimeStatePersistence: { [weak self] tab in
                self?.tabManager.scheduleRuntimeStatePersistence(for: tab)
            }
        )
    }

    var bookmarksPageBrowserContext: BookmarksPageBrowserContext {
        BookmarksPageBrowserContext(
            bookmarkManager: bookmarkManager,
            faviconService: dataServices.faviconService,
            currentProfile: { [weak self] in
                self?.currentProfile
            },
            currentProfileUpdates: $currentProfile.eraseToAnyPublisher(),
            currentTab: { [weak self] windowState in
                self?.currentTab(for: windowState)
            },
            openHistoryURLsInNewTabs: { [weak self] urls, windowState in
                self?.openHistoryURLsInNewTabs(urls, in: windowState)
            },
            openHistoryURLsInNewWindow: { [weak self] urls in
                self?.openHistoryURLsInNewWindow(urls)
            },
            openBookmarkURL: { [weak self] url, windowState, preferredOpenMode in
                self?.openBookmarkURL(
                    url,
                    in: windowState,
                    preferredOpenMode: preferredOpenMode
                )
            },
            importBookmarksFromMenu: { [weak self] in
                self?.importBookmarksFromMenu()
            },
            exportBookmarksFromMenu: { [weak self] in
                self?.exportBookmarksFromMenu()
            },
            scheduleRuntimeStatePersistence: { [weak self] tab in
                self?.tabManager.scheduleRuntimeStatePersistence(for: tab)
            }
        )
    }
}
