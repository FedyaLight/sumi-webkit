import Foundation

@MainActor
final class ClosedTabDestinationResolver {
    private let spaces: TabSpaceCollectionStateOwner
    private let windows: WindowRegistry

    init(
        spaces: TabSpaceCollectionStateOwner,
        windows: WindowRegistry
    ) {
        self.spaces = spaces
        self.windows = windows
    }

    var activeWindow: BrowserWindowState? {
        windows.activeWindow
    }

    func destinationSpace(
        sourceSpaceID: UUID?,
        sourceProfileID: UUID?,
        fallbackWindow: BrowserWindowState?
    ) -> Space? {
        if let sourceSpaceID,
           let sourceSpace = spaces.space(with: sourceSpaceID) {
            return sourceSpace
        }
        if let spaceID = fallbackWindow?.currentSpaceId,
           let windowSpace = spaces.space(with: spaceID) {
            return windowSpace
        }
        if let sourceProfileID,
           let profileSpace = spaces.firstSpace(forProfile: sourceProfileID) {
            return profileSpace
        }
        if let profileID = fallbackWindow?.currentProfileId {
            return spaces.firstSpace(forProfile: profileID)
        }
        return nil
    }
}
