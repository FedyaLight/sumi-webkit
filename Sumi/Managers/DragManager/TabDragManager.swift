//
//  TabDragManager.swift
//  Sumi
//
//  Drag container types and operation structs used by TabManager.handleDragOperation().
//

import SwiftUI

@MainActor
class TabDragManager: ObservableObject {
    static let shared = TabDragManager()

    enum DragContainer: Equatable {
        case none
        case essentials
        case spacePinned(UUID) // space ID
        case spaceRegular(UUID) // space ID
        case folder(UUID) // folder ID
        
        var spaceId: UUID? {
            switch self {
            case .spacePinned(let id): return id
            case .spaceRegular(let id): return id
            default: return nil
            }
        }
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
    let fromContainer: TabDragManager.DragContainer
    let fromIndex: Int
    let toContainer: TabDragManager.DragContainer
    let toIndex: Int
    let toSpaceId: UUID?
    let toProfileId: UUID?

    init(
        payload: Payload,
        fromContainer: TabDragManager.DragContainer,
        fromIndex: Int,
        toContainer: TabDragManager.DragContainer,
        toIndex: Int,
        toSpaceId: UUID?,
        toProfileId: UUID? = nil
    ) {
        self.payload = payload
        self.fromContainer = fromContainer
        self.fromIndex = fromIndex
        self.toContainer = toContainer
        self.toIndex = toIndex
        self.toSpaceId = toSpaceId
        self.toProfileId = toProfileId
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

    var isMovingBetweenContainers: Bool {
        return fromContainer != toContainer
    }

    var isReordering: Bool {
        return fromContainer == toContainer && fromIndex != toIndex
    }
}
