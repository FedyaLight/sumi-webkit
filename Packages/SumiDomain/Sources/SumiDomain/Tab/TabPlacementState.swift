import Foundation

public struct TabPlacementState: Equatable, Sendable {
    public var spaceId: UUID?
    public var index = 0
    public var isPinned = false
    public var isSpacePinned = false
    public var folderId: UUID?
    public var shortcutPinId: UUID?
    public var shortcutPinRole: ShortcutPinRole?
    public var isShortcutLiveInstance = false

    public init() {}

    public mutating func bindToShortcutPin(id: UUID, role: ShortcutPinRole) {
        shortcutPinId = id
        shortcutPinRole = role
        isShortcutLiveInstance = true
    }

    public mutating func clearShortcutBinding() {
        shortcutPinId = nil
        shortcutPinRole = nil
        isShortcutLiveInstance = false
    }
}
