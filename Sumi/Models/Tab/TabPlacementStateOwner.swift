import Foundation

@MainActor
final class TabPlacementStateOwner {
    var spaceId: UUID?
    var index = 0
    var isPinned = false
    var isSpacePinned = false
    var folderId: UUID?
    var shortcutPinId: UUID?
    var shortcutPinRole: ShortcutPinRole?
    var isShortcutLiveInstance = false

    func bindToShortcutPin(_ pin: ShortcutPin) {
        shortcutPinId = pin.id
        shortcutPinRole = pin.role
        isShortcutLiveInstance = true
    }

    func clearShortcutBinding() {
        shortcutPinId = nil
        shortcutPinRole = nil
        isShortcutLiveInstance = false
    }
}
