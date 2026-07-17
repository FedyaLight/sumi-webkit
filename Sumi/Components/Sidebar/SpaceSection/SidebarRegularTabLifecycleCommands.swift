import Foundation

@MainActor
final class SidebarRegularTabLifecycleCommands {
    private let closure: TabClosureService

    init(closure: TabClosureService) {
        self.closure = closure
    }

    func clearRegularTabs(for spaceID: UUID) {
        closure.clearRegularTabs(for: spaceID)
    }

    func closeAllTabsBelow(_ tab: Tab) {
        closure.closeAllTabsBelow(tab)
    }
}
