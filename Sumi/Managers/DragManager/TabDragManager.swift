//
//  TabDragManager.swift
//  Sumi
//
//  Drag container types and operation structs used by TabManager.handleDragOperation().
//

import Foundation

enum TabDragManager {
    enum DragContainer: Equatable {
        case none
        case essentials
        case spacePinned(UUID) // space ID
        case spaceRegular(UUID) // space ID
        case folder(UUID) // folder ID
    }
}

extension Notification.Name {
    static let tabDragDidEnd = Notification.Name("tabDragDidEnd")
    static let tabManagerDidLoadInitialData = Notification.Name("tabManagerDidLoadInitialData")
}

// MARK: - Drag Operation Result
struct DragOperation {
    enum Payload {
        case tab(Tab)
        case folder(TabFolder)
        case pin(ShortcutPin)
    }

    let payload: Payload
    let scope: SidebarDragScope
    let fromContainer: TabDragManager.DragContainer
    let toContainer: TabDragManager.DragContainer
    let toIndex: Int

    init(
        payload: Payload,
        scope: SidebarDragScope,
        fromContainer: TabDragManager.DragContainer,
        toContainer: TabDragManager.DragContainer,
        toIndex: Int
    ) {
        self.payload = payload
        self.scope = scope
        self.fromContainer = fromContainer
        self.toContainer = toContainer
        self.toIndex = toIndex
    }

    var tab: Tab? {
        guard case .tab(let tab) = payload else { return nil }
        return tab
    }

    var folder: TabFolder? {
        guard case .folder(let folder) = payload else { return nil }
        return folder
    }

    var pin: ShortcutPin? {
        guard case .pin(let pin) = payload else { return nil }
        return pin
    }

}
