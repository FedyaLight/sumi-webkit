import AppKit
import Foundation

struct TabFolderUngroupPreparation {
    let spaceID: UUID
    let folderID: UUID
    let isLiveFolder: Bool
    let parentFolderID: UUID?
    let remainingFolders: [TabFolder]
    let liftedParentItems: [TabFolderContainerItem]
    let liveTabs: [Tab]
}
