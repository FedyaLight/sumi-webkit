import Foundation
import SumiDomain

/// Validates durable shortcut container identity without consulting browser
/// runtime state. Live-folder policy remains a command-layer concern.
@MainActor
final class ShortcutPinDestinationValidator {
    private let spaces: TabSpaceCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        folders: TabFolderCollectionStateOwner
    ) {
        self.spaces = spaces
        self.folders = folders
    }

    func accepts(
        role: ShortcutPinRole,
        spaceId: UUID?,
        folderId: UUID?
    ) -> Bool {
        switch role {
        case .favorite:
            return spaceId == nil && folderId == nil
        case .spacePinned:
            guard let spaceId, spaces.contains(spaceId: spaceId) else {
                return false
            }
            guard let folderId else { return true }
            return folders.spaceId(for: folderId) == spaceId
        }
    }
}
