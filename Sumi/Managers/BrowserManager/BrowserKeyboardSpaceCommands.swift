import Foundation

/// Active-window Space cycling and folder visibility commands.
@MainActor
final class BrowserKeyboardSpaceCommands {
    private let shell: BrowserShellRuntime
    private let spaces: TabSpaceCollectionStateOwner
    private let transitions: BrowserWindowSpaceTransitionService
    private let folderOpenState: TabFolderOpenStateService
    private let persistence: WindowSessionPersistenceCoordinator

    init(
        shell: BrowserShellRuntime,
        spaces: TabSpaceCollectionStateOwner,
        transitions: BrowserWindowSpaceTransitionService,
        folderOpenState: TabFolderOpenStateService,
        persistence: WindowSessionPersistenceCoordinator
    ) {
        self.shell = shell
        self.spaces = spaces
        self.transitions = transitions
        self.folderOpenState = folderOpenState
        self.persistence = persistence
    }

    func selectRelativeSpace(offset: Int) {
        guard let activeWindow = shell.windowRegistry.activeWindow,
              let currentSpaceID = activeWindow.currentSpaceId,
              let currentIndex = spaces.spaces.firstIndex(where: {
                  $0.id == currentSpaceID
              }),
              spaces.spaces.isEmpty == false else {
            return
        }

        let nextIndex = (
            currentIndex + offset + spaces.spaces.count
        ) % spaces.spaces.count
        transitions.setActiveSpace(spaces.spaces[nextIndex], in: activeWindow)
    }

    func expandAllFoldersInActiveSpace() {
        guard let activeWindow = shell.windowRegistry.activeWindow,
              let currentSpaceID = activeWindow.currentSpaceId else {
            return
        }
        folderOpenState.setAllFolders(open: true, in: currentSpaceID)
        persistence.persist(activeWindow)
    }
}
