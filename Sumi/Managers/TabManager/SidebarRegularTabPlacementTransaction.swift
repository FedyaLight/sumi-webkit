import Foundation

@MainActor
final class SidebarRegularTabPlacementTransaction {
    private let regularTabs: RegularTabCollectionOwner
    private let shortcutRemoval: ShortcutContainerRemovalOwner
    private let persistence: TabStructuralPersistenceService

    init(
        regularTabs: RegularTabCollectionOwner,
        shortcutRemoval: ShortcutContainerRemovalOwner,
        persistence: TabStructuralPersistenceService
    ) {
        self.regularTabs = regularTabs
        self.shortcutRemoval = shortcutRemoval
        self.persistence = persistence
    }

    func reorder(_ tab: Tab, in spaceID: UUID, to index: Int) -> Bool {
        regularTabs.reorderRegularTabs(tab, in: spaceID, to: index)
    }

    func tabs(in spaceID: UUID) -> [Tab] {
        regularTabs.tabs(in: spaceID)
    }

    func place(_ tab: Tab, in spaceID: UUID, at index: Int) -> Bool {
        guard regularTabs.place(
            tab,
            in: spaceID,
            at: index,
            removingFromSource: { [shortcutRemoval] in
                shortcutRemoval.removeFromCurrentContainer(tab)
            }
        ) else {
            return false
        }
        persistence.scheduleStructuralPersistence()
        return true
    }
}
