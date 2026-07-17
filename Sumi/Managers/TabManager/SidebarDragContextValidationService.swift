import Foundation
import SumiDomain

@MainActor
final class SidebarDragContextValidationService {
    private let spaces: TabSpaceCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner
    ) {
        self.spaces = spaces
        self.folders = folders
        self.pins = pins
    }

    func validate(_ operation: DragOperation) -> Bool {
        let isCurrentContext = SidebarDragOperationContextValidator.validate(
            operation: operation,
            spaceProfileId: spaces.profileId(for: operation.scope.spaceId),
            folderSpaceId: folders.spaceId,
            shortcutPin: pins.shortcutPin
        )
        guard isCurrentContext else {
            RuntimeDiagnostics.emit(
                "⚠️ Rejected sidebar drag outside current context: \(operation)"
            )
            return false
        }
        return true
    }
}
