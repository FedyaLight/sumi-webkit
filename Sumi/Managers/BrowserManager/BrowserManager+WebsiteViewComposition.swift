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
                _ = self?.webViewRoutingService.repairFailedPage(
                    tabID,
                    in: windowID,
                    useNativeSnapshot: useNative
                )
            },
            spaces: spaceStateOwner,
            dragOperations: sidebarDragRouter
        )
    }
}
