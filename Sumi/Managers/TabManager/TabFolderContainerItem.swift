import AppKit
import Foundation

enum TabFolderContainerItem: Hashable {
    case folder(UUID)
    case shortcut(UUID)

    var id: UUID {
        switch self {
        case .folder(let id), .shortcut(let id):
            return id
        }
    }
}
