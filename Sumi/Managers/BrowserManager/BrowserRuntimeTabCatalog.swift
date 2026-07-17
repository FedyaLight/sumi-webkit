import Foundation

@MainActor
final class BrowserRuntimeTabCatalog {
    private let regularTabs: TabCollectionMembershipOwner
    private let windows: WindowRegistry

    init(
        regularTabs: TabCollectionMembershipOwner,
        windows: WindowRegistry
    ) {
        self.regularTabs = regularTabs
        self.windows = windows
    }

    func allKnownTabs() -> [Tab] {
        var seen = Set<UUID>()
        var tabs: [Tab] = []

        func append(_ tab: Tab) {
            guard seen.insert(tab.id).inserted else { return }
            tabs.append(tab)
        }

        regularTabs.allTabs().forEach(append)
        windows.windows.values.flatMap(\.ephemeralTabs).forEach(append)
        return tabs
    }
}
