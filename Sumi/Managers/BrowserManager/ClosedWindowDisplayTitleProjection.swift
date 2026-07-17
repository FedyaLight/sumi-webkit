import Foundation

@MainActor
final class ClosedWindowDisplayTitleProjection {
    private let windowTabs: BrowserWindowTabContext
    private let spaces: TabSpaceCollectionStateOwner

    init(
        windowTabs: BrowserWindowTabContext,
        spaces: TabSpaceCollectionStateOwner
    ) {
        self.windowTabs = windowTabs
        self.spaces = spaces
    }

    func title(for window: BrowserWindowState) -> String {
        if let currentTab = windowTabs.currentTab(for: window) {
            return currentTab.name
        }
        if let currentSpaceID = window.currentSpaceId,
           let currentSpace = spaces.space(with: currentSpaceID) {
            return currentSpace.name
        }
        return "Window"
    }
}
