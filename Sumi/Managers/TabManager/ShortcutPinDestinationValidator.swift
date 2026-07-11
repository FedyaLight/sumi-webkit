import Foundation
import SumiDomain

/// Validates durable shortcut container identity without consulting browser
/// runtime state. Live-folder policy remains a command-layer concern.
@MainActor
final class ShortcutPinDestinationValidator {
    private let spaceExists: (UUID) -> Bool
    private let folderSpaceId: (UUID) -> UUID?

    init(
        spaceExists: @escaping (UUID) -> Bool,
        folderSpaceId: @escaping (UUID) -> UUID?
    ) {
        self.spaceExists = spaceExists
        self.folderSpaceId = folderSpaceId
    }

    func accepts(
        role: ShortcutPinRole,
        spaceId: UUID?,
        folderId: UUID?
    ) -> Bool {
        switch role {
        case .essential:
            return spaceId == nil && folderId == nil
        case .spacePinned:
            guard let spaceId, spaceExists(spaceId) else { return false }
            guard let folderId else { return true }
            return folderSpaceId(folderId) == spaceId
        }
    }
}
