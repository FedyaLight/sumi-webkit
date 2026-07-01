import Combine
import SwiftUI

/// Builds the browser contexts consumed by website/native-surface root views
/// (web content, history page, bookmarks page) from browser subsystems.
@MainActor
enum WebsiteViewContextFactory {
    static func websiteViewBrowserContext(
        for browserManager: BrowserManager,
        sidebarDragState: SidebarDragState
    ) -> WebsiteViewBrowserContext {
        WebsiteViewBrowserContext(
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            workspaceTheme: { [weak browserManager] spaceId in
                browserManager?.space(for: spaceId)?.workspaceTheme
            },
            makeWebContentContext: {
                BrowserManagerWindowWebContentContext(
                    browserManager: browserManager,
                    sidebarDragState: sidebarDragState
                )
            }
        )
    }

    static func nativeSurfaceRootBuilders(
        for browserManager: BrowserManager
    ) -> WebsiteNativeSurfaceRootBuilders {
        WebsiteNativeSurfaceRootBuilders(
            history: { [weak browserManager] windowState in
                guard let browserManager else { return AnyView(EmptyView()) }
                return AnyView(
                    SumiHistoryTabRootView(
                        browserContext: historyPageBrowserContext(for: browserManager),
                        windowState: windowState
                    )
                )
            },
            bookmarks: { [weak browserManager] windowState in
                guard let browserManager else { return AnyView(EmptyView()) }
                return AnyView(
                    SumiBookmarksTabRootView(
                        browserContext: bookmarksPageBrowserContext(for: browserManager),
                        windowState: windowState
                    )
                )
            },
            settings: { [weak browserManager] windowState in
                guard let browserManager else { return AnyView(EmptyView()) }
                return AnyView(
                    SumiSettingsTabRootView(
                        browserManager: browserManager,
                        windowState: windowState
                    )
                    .environmentObject(browserManager.extensionsModule.surfaceStore)
                )
            }
        )
    }

    static func historyPageBrowserContext(
        for browserManager: BrowserManager
    ) -> HistoryPageBrowserContext {
        HistoryPageBrowserContext(
            historyManager: browserManager.historyManager,
            faviconService: browserManager.dataServices.faviconService,
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            currentProfileUpdates: browserManager.$currentProfile.eraseToAnyPublisher(),
            nativeModalPresentationUpdates: browserManager.$nativeModalPresentation
                .map { _ in () }
                .eraseToAnyPublisher(),
            isNativeModalPresented: { [weak browserManager] windowId in
                guard let windowId else { return false }
                return browserManager?.nativeDialogPresentationOwner
                    .isNativeModalPresented(in: windowId) ?? false
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            openHistoryURL: { [weak browserManager] url, windowState, preferredOpenMode in
                browserManager?.historyNavigationOwner.openHistoryURL(
                    url,
                    in: windowState,
                    preferredOpenMode: preferredOpenMode
                )
            },
            openHistoryURLsInNewTabs: { [weak browserManager] urls, windowState in
                browserManager?.historyNavigationOwner.openHistoryURLsInNewTabs(
                    urls,
                    in: windowState
                )
            },
            presentBrowsingDataSheet: { [weak browserManager] windowState in
                browserManager?.nativeDialogPresentationOwner.presentBrowsingDataSheet(
                    windowState: windowState
                )
            },
            scheduleRuntimeStatePersistence: { [weak browserManager] tab in
                browserManager?.tabManager.scheduleRuntimeStatePersistence(for: tab)
            }
        )
    }

    static func bookmarksPageBrowserContext(
        for browserManager: BrowserManager
    ) -> BookmarksPageBrowserContext {
        BookmarksPageBrowserContext(
            bookmarkManager: browserManager.bookmarkManager,
            faviconService: browserManager.dataServices.faviconService,
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            currentProfileUpdates: browserManager.$currentProfile.eraseToAnyPublisher(),
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            openHistoryURLsInNewTabs: { [weak browserManager] urls, windowState in
                browserManager?.historyNavigationOwner.openHistoryURLsInNewTabs(
                    urls,
                    in: windowState
                )
            },
            openHistoryURLsInNewWindow: { [weak browserManager] urls in
                browserManager?.historyNavigationOwner.openHistoryURLsInNewWindow(urls)
            },
            openBookmarkURL: { [weak browserManager] url, windowState, preferredOpenMode in
                browserManager?.bookmarkCommandOwner.openBookmarkURL(
                    url,
                    in: windowState,
                    preferredOpenMode: preferredOpenMode
                )
            },
            importBookmarksFromMenu: { [weak browserManager] in
                browserManager?.bookmarkCommandOwner.importBookmarksFromMenu()
            },
            exportBookmarksFromMenu: { [weak browserManager] in
                browserManager?.bookmarkCommandOwner.exportBookmarksFromMenu()
            },
            scheduleRuntimeStatePersistence: { [weak browserManager] tab in
                browserManager?.tabManager.scheduleRuntimeStatePersistence(for: tab)
            }
        )
    }
}
