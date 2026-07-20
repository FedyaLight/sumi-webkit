import Foundation
import SumiDomain

/// Resolves the launcher's current durable placement.
@MainActor
struct ShortcutSplitLauncherDestinationResolver {
    private let folders: TabFolderCollectionStateOwner

    init(folders: TabFolderCollectionStateOwner) {
        self.folders = folders
    }

    func destination(
        for _: SplitMember,
        pin: ShortcutPin
    ) -> ShortcutSplitLauncherDestination? {
        switch pin.role {
        case .essential:
            guard let targetProfileID = pin.profileId else {
                return nil
            }
            return ShortcutSplitLauncherDestination(
                role: .essential,
                profileId: targetProfileID,
                spaceId: nil,
                folderId: nil,
                index: pin.index
            )
        case .spacePinned:
            guard let spaceID = pin.spaceId else { return nil }
            let validFolderID = pin.folderId.flatMap {
                folders.spaceId(for: $0) == spaceID ? $0 : nil
            }
            return ShortcutSplitLauncherDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceID,
                folderId: validFolderID,
                index: pin.index
            )
        }
    }
}
