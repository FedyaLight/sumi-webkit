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
        activate(spaces.spaces[nextIndex], in: windowState)
    }

    /// Activates the space at `index` in catalog order. Positions past the end
    /// are a no-op: a shortcut may outlive the space it was bound to.
    func selectSpace(
        atIndex index: Int,
        in windowState: BrowserWindowState
    ) {
        // Private windows expose one ephemeral space and intentionally hide the
        // regular spaces strip. An ordinal regular-space command is therefore
        // unavailable rather than a path back into the durable catalog.
        guard !windowState.isIncognito,
              spaces.spaces.indices.contains(index)
        else { return }
        activate(spaces.spaces[index], in: windowState)
    }

    func expandAllFolders(in windowState: BrowserWindowState) {
        guard let currentSpaceID = windowState.currentSpaceId else {
            return
        }
        folderOpenState.setAllFolders(open: true, in: currentSpaceID)
        persistence.persist(windowState)
    }

    private func activate(
        _ space: Space,
        in windowState: BrowserWindowState
    ) {
        if windowState.presentationState.spaceSwitch
            .requestAnimatedSwitch(to: space.id) {
            return
        }
        transitions.setActiveSpace(space, in: windowState)
    }
}
