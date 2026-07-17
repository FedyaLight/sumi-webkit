import Foundation

@MainActor
final class RegularTabClosureTargetQuery {
    private let regularTabs: RegularTabCollectionOwner
    private let selection: TabSelectionStateOwner

    init(
        regularTabs: RegularTabCollectionOwner,
        selection: TabSelectionStateOwner
    ) {
        self.regularTabs = regularTabs
        self.selection = selection
    }

    func tabIDsBelow(_ tab: Tab) -> [UUID] {
        guard tab.spaceId != nil else { return [] }
        return regularTabs.tabsBelow(tab)?.map(\.id) ?? []
    }

    func regularTabIDsToClear(in spaceID: UUID) -> [UUID] {
        let tabs = regularTabs.tabs(in: spaceID)
        guard tabs.isEmpty == false else { return [] }
        let inactiveIDs = tabs.compactMap {
            $0.id == selection.currentTab?.id ? nil : $0.id
        }
        if inactiveIDs.isEmpty == false { return inactiveIDs }
        guard let active = selection.currentTab,
              active.spaceId == spaceID,
              tabs.contains(where: { $0.id == active.id }) else {
            return []
        }
        return [active.id]
    }
}
