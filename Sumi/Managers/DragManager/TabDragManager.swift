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

extension TabDragManager.DragContainer: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case id
    }

    private enum Kind: String, Codable {
        case none
        case essentials
        case spacePinned
        case spaceRegular
        case folder
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case .essentials:
            try container.encode(Kind.essentials, forKey: .kind)
        case .spacePinned(let id):
            try container.encode(Kind.spacePinned, forKey: .kind)
            try container.encode(id, forKey: .id)
        case .spaceRegular(let id):
            try container.encode(Kind.spaceRegular, forKey: .kind)
            try container.encode(id, forKey: .id)
        case .folder(let id):
            try container.encode(Kind.folder, forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .none:
            self = .none
        case .essentials:
            self = .essentials
        case .spacePinned:
            self = .spacePinned(try container.decode(UUID.self, forKey: .id))
        case .spaceRegular:
            self = .spaceRegular(try container.decode(UUID.self, forKey: .id))
        case .folder:
            self = .folder(try container.decode(UUID.self, forKey: .id))
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
