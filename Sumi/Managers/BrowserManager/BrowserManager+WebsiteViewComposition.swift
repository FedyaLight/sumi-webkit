import Foundation

@MainActor
extension BrowserManager {
    func composeWebsiteViewBrowserContext() -> WebsiteViewBrowserContext {
        let shell = shellRuntime

        return WebsiteViewContextFactory.websiteViewBrowserContext(
            windowTabs: shell.windowTabs,
            membership: tabCollectionMembershipOwner,
            windowVisuals: shell.windowVisuals,
            spaces: spaceStateOwner,
            dragOperations: sidebarDragRouter
        )
    }
}
