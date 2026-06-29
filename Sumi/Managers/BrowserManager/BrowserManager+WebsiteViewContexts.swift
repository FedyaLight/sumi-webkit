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
                        browserManager: self,
                        windowState: windowState
                    )
                )
            },
            bookmarks: { [weak self] windowState in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    SumiBookmarksTabRootView(
                        browserManager: self,
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
}
