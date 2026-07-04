import Foundation

@MainActor
final class TabSelectionStateOwner {
    private(set) var currentTab: Tab?

    var currentTabId: UUID? {
        currentTab?.id
    }

    func replaceCurrentTab(_ tab: Tab?) {
        currentTab = tab
    }

    func clearCurrentTabIfMatches(_ tabId: UUID) {
        if currentTab?.id == tabId {
            currentTab = nil
        }
    }
}
