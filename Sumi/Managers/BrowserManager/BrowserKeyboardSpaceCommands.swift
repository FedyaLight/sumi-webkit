import Foundation

/// Active-window Space cycling and folder visibility commands.
@MainActor
final class BrowserKeyboardSpaceCommands {
    private let spaces: TabSpaceCollectionStateOwner
    private let transitions: BrowserWindowSpaceTransitionService
    private let folderOpenState: TabFolderOpenStateService
    private let persistence: WindowSessionPersistenceCoordinator

    init(
        spaces: TabSpaceCollectionStateOwner,
        transitions: BrowserWindowSpaceTransitionService,
        folderOpenState: TabFolderOpenStateService,
        persistence: WindowSessionPersistenceCoordinator
    ) {
        self.spaces = spaces
        self.transitions = transitions
        self.folderOpenState = folderOpenState
        self.persistence = persistence
    }

    func selectRelativeSpace(
        offset: Int,
        in windowState: BrowserWindowState
    ) {
        guard let currentSpaceID = windowState.currentSpaceId,
              let currentIndex = spaces.spaces.firstIndex(where: {
                  $0.id == currentSpaceID
              }),
              spaces.spaces.isEmpty == false else {
            return
        }

        let nextIndex = (
            currentIndex + offset + spaces.spaces.count
        ) % spaces.spaces.count
        transitions.setActiveSpace(spaces.spaces[nextIndex], in: windowState)
    }

    func expandAllFolders(in windowState: BrowserWindowState) {
        guard let currentSpaceID = windowState.currentSpaceId else {
            return
        }
        folderOpenState.setAllFolders(open: true, in: currentSpaceID)
        persistence.persist(windowState)
    }
}
