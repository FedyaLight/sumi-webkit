import Foundation

/// Read-only regular-tab residence and catalog projection for sidebar views.
@MainActor
final class SidebarRegularTabCatalog {
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: RegularTabCollectionOwner
    private let membership: TabCollectionMembershipOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: RegularTabCollectionOwner,
        membership: TabCollectionMembershipOwner
    ) {
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.membership = membership
    }

    var allSpaces: [Space] {
        spaces.spaces
    }

    func tabs(in space: Space, windowState: BrowserWindowState) -> [Tab] {
        if windowState.isIncognito {
            return windowState.ephemeralTabs.sorted { $0.index < $1.index }
        }
        return regularTabs.tabs(in: space)
    }

    func hasPersistedTabs(in space: Space) -> Bool {
        regularTabs.tabs(in: space).isEmpty == false
    }

    func tab(for id: UUID) -> Tab? {
        membership.tab(for: id)
    }
}
