import Foundation

@MainActor
final class ClosedShortcutLauncherDestinationResolver {
    private let folders: TabFolderCollectionStateOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let spaces: TabSpaceCollectionStateOwner
    private let profiles: ProfileManager

    init(
        folders: TabFolderCollectionStateOwner,
        runtimeConnection: TabRuntimePortConnection,
        spaces: TabSpaceCollectionStateOwner,
        profiles: ProfileManager
    ) {
        self.folders = folders
        self.runtimeConnection = runtimeConnection
        self.spaces = spaces
        self.profiles = profiles
    }

    func favoriteProfileID(
        for pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState?
    ) -> UUID? {
        if let profileID = pinState.profileId,
           profiles.profiles.contains(where: { $0.id == profileID }) {
            return profileID
        }
        if let profileID = fallbackWindow?.currentProfileId,
           profiles.profiles.contains(where: { $0.id == profileID }) {
            return profileID
        }
        return nil
    }

    func spaceID(
        for pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState?
    ) -> UUID? {
        if let spaceID = pinState.spaceId,
           spaces.contains(spaceId: spaceID) {
            return spaceID
        }
        if let spaceID = fallbackWindow?.currentSpaceId,
           spaces.contains(spaceId: spaceID) {
            return spaceID
        }
        guard let profileID = fallbackWindow?.currentProfileId else {
            return nil
        }
        return spaces.firstSpace(forProfile: profileID)?.id
    }

    func folderID(
        _ folderID: UUID?,
        in spaceID: UUID
    ) -> UUID? {
        guard let folderID,
              folders.spaceId(for: folderID) == spaceID,
              runtimeConnection.current?.isLiveFolder(folderID) != true else {
            return nil
        }
        return folderID
    }
}
