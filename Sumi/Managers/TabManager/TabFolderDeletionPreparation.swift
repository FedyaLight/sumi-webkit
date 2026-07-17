import AppKit
import Foundation

struct TabFolderDeletionPreparation {
    let spaceID: UUID
    let deletedFolderIDs: Set<UUID>
    let parentFolderID: UUID?
    let remainingFolders: [TabFolder]
    let existingPins: [ShortcutPin]
    let remainingPins: [ShortcutPin]
    let deletedPins: [ShortcutPin]
    let deletedPinIDs: Set<UUID>
    let liveTabIDs: [UUID]
    let remainingParentItems: [TabFolderContainerItem]
}
