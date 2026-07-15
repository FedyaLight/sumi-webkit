import Foundation

@MainActor
final class TabActiveSpaceSelectionUpdater {
    private let spaces: TabSpaceCollectionStateOwner
    private let persistence: TabStructuralPersistenceService

    init(
        spaces: TabSpaceCollectionStateOwner,
        persistence: TabStructuralPersistenceService
    ) {
        self.spaces = spaces
        self.persistence = persistence
    }

    func update(
        for tab: Tab,
        refreshCurrentSpaceReference: Bool
    ) {
        var didChangePersistenceState = false
        if let spaceID = tab.spaceId,
           let space = spaces.space(with: spaceID) {
            if space.activeTabId != tab.id {
                space.activeTabId = tab.id
                didChangePersistenceState = true
            }
            if refreshCurrentSpaceReference || spaces.currentSpace?.id != space.id {
                spaces.replaceCurrentSpace(space)
            }
        } else if let currentSpace = spaces.currentSpace,
                  currentSpace.activeTabId != tab.id {
            currentSpace.activeTabId = tab.id
            didChangePersistenceState = true
        }

        if didChangePersistenceState {
            persistence.markSpacesSnapshotDirty()
        }
    }
}
