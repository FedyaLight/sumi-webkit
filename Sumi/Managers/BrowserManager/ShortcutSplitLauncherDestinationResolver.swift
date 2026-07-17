import Foundation
import SumiDomain

/// Resolves persisted return placement against the current launcher catalog.
@MainActor
struct ShortcutSplitLauncherDestinationResolver {
    private let folders: TabFolderCollectionStateOwner
    private let spacePinnedStructure: SpacePinnedStructureOwner

    init(
        folders: TabFolderCollectionStateOwner,
        spacePinnedStructure: SpacePinnedStructureOwner
    ) {
        self.folders = folders
        self.spacePinnedStructure = spacePinnedStructure
    }

    func destination(
        for member: SplitMember,
        pin: ShortcutPin
    ) -> ShortcutSplitLauncherDestination? {
        guard let returnPlacement = member.returnPlacement else { return nil }
        switch returnPlacement {
        case .essential(let profileID, let index):
            guard let targetProfileID = profileID ?? pin.profileId else {
                return nil
            }
            return ShortcutSplitLauncherDestination(
                role: .essential,
                profileId: targetProfileID,
                spaceId: nil,
                folderId: nil,
                index: index
            )
        case .spacePinned(let spaceID, let folderID, let index):
            let validFolderID = folderID.flatMap {
                folders.spaceId(for: $0) == spaceID ? $0 : nil
            }
            return ShortcutSplitLauncherDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceID,
                folderId: validFolderID,
                index: index
            )
        case .generatedSpacePinnedFromRegular(let spaceID, _):
            return ShortcutSplitLauncherDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceID,
                folderId: nil,
                index: spacePinnedStructure
                    .topLevelSpacePinnedItems(for: spaceID).count
            )
        }
    }
}
