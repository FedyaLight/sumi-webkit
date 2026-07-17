import AppKit
import Foundation

@MainActor
enum TabFolderPlacementIntent {
    case reorderTopLevel(spaceID: UUID, targetIndex: Int)
    case move(parentFolderID: UUID?, spaceID: UUID, targetIndex: Int)
}
