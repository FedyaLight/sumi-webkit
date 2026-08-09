import Foundation

@MainActor
extension BrowserManager {
    func composeWebsiteViewBrowserContext() -> WebsiteViewBrowserContext {
        let shell = shellRuntime

        return WebsiteViewContextFactory.websiteViewBrowserContext(
            windowTabs: shell.windowTabs,
            membership: tabCollectionMembershipOwner,
            windowVisuals: shell.windowVisuals,
            repairFailure: { [weak self] tabID, windowID, useNative in
                guard let self,
                      let tab = self.tabCollectionMembershipOwner.tab(
                        for: tabID
                      ) else { return }
                _ = self.webViewRuntime.repairFailedPage(
                    tab,
                    in: windowID,
                    useNativeSnapshot: useNative
                )
            },
            spaces: spaceStateOwner,
            dragOperations: sidebarDragRouter
        )
    }
}
