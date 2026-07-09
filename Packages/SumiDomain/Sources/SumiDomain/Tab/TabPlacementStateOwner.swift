import Foundation

@MainActor
public final class TabPlacementStateOwner {
    public var spaceId: UUID?
    public var index = 0
    public var isPinned = false
    public var isSpacePinned = false
    public var folderId: UUID?
    public var shortcutPinId: UUID?
    public var shortcutPinRole: ShortcutPinRole?
    public var isShortcutLiveInstance = false

    public init() {}

    public func bindToShortcutPin(id: UUID, role: ShortcutPinRole) {
        shortcutPinId = id
        shortcutPinRole = role
        isShortcutLiveInstance = true
    }

    public func clearShortcutBinding() {
        shortcutPinId = nil
        shortcutPinRole = nil
        isShortcutLiveInstance = false
    }
}
