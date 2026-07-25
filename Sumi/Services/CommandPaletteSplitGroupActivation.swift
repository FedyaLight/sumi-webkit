import Foundation

/// Activates a split group chosen in the command palette. A group living in
/// another space is focused first and only then does the window transition to
/// that space, so a failed focus never leaves the window on a foreign space.
@MainActor
final class CommandPaletteSplitGroupActivation {
    private let splitGroups: SplitGroupStore
    private let splitFocus: SplitShortcutFocusService
    private let spaces: TabSpaceCollectionStateOwner
    /// Resolved on use, not at composition. The space-transition service is
    /// reachable from the URL-bar bundle, which in turn composes the command
    /// palette — holding it eagerly would close that cycle and recurse during
    /// lazy initialization.
    private let spaceTransitions:
        @MainActor () -> BrowserWindowSpaceTransitionService

    init(
        splitGroups: SplitGroupStore,
        splitFocus: SplitShortcutFocusService,
        spaces: TabSpaceCollectionStateOwner,
        spaceTransitions:
            @escaping @MainActor () -> BrowserWindowSpaceTransitionService
    ) {
        self.splitGroups = splitGroups
        self.splitFocus = splitFocus
        self.spaces = spaces
        self.spaceTransitions = spaceTransitions
    }

    func activate(groupID: UUID, in window: BrowserWindowState) -> Bool {
        guard let group = splitGroups.group(id: groupID) else { return false }
        guard let spaceID = group.container.spaceId,
              spaceID != window.currentSpaceId else {
            return splitFocus.activateSplitGroup(group, in: window)
        }
        guard let space = spaces.space(with: spaceID),
              splitFocus.activateSplitGroup(group, in: window)
        else { return false }
        spaceTransitions().setActiveSpace(space, in: window)
        return true
    }
}
