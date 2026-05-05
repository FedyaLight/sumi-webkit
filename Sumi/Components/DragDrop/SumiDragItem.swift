//
//  SumiDragItem.swift
//  Sumi
//

import Foundation
import AppKit

extension NSPasteboard.PasteboardType {
    static let sumiTabItem = NSPasteboard.PasteboardType("com.sumi.tab-drag-item")
}

// MARK: - Drop Zone Identity

enum DropZoneID: Hashable {
    case essentials
    case spacePinned(UUID)
    case spaceRegular(UUID)
    case folder(UUID)

    var asDragContainer: TabDragManager.DragContainer {
        switch self {
        case .essentials:
            return .essentials
        case .spacePinned(let spaceId):
            return .spacePinned(spaceId)
        case .spaceRegular(let spaceId):
            return .spaceRegular(spaceId)
        case .folder(let folderId):
            return .folder(folderId)
        }
    }
}

struct SidebarDragScope: Equatable {
    let windowId: UUID?
    let spaceId: UUID
    let profileId: UUID?
    let sourceContainer: TabDragManager.DragContainer
    let sourceItemId: UUID
    let sourceItemKind: SumiDragItemKind

    @MainActor
    init?(
        windowState: BrowserWindowState?,
        sourceZone: DropZoneID,
        item: SumiDragItem
    ) {
        guard let spaceId = windowState?.currentSpaceId else {
            return nil
        }

        self.windowId = windowState?.id
        self.spaceId = spaceId
        self.profileId = windowState?.currentProfileId
        self.sourceContainer = sourceZone.asDragContainer
        self.sourceItemId = item.tabId
        self.sourceItemKind = item.kind
    }

    func matches(windowId targetWindowId: UUID?) -> Bool {
        guard let windowId, let targetWindowId else {
            return true
        }
        return windowId == targetWindowId
    }

    func matches(profileId targetProfileId: UUID?) -> Bool {
        guard let profileId, let targetProfileId else {
            return true
        }
        return profileId == targetProfileId
    }
}

// MARK: - Drag Item

enum SumiDragItemKind: String, Codable, Equatable {
    case tab
    case folder
}

struct SumiDragItem: Codable, Equatable {
    let tabId: UUID
    var kind: SumiDragItemKind
    var title: String
    var urlString: String

    init(tabId: UUID, kind: SumiDragItemKind = .tab, title: String, urlString: String = "") {
        self.tabId = tabId
        self.kind = kind
        self.title = title
        self.urlString = urlString
    }

    static func folder(folderId: UUID, title: String) -> SumiDragItem {
        SumiDragItem(tabId: folderId, kind: .folder, title: title)
    }
}

extension SumiDragItem {
    func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        do {
            let data = try JSONEncoder().encode(self)
            item.setData(data, forType: .sumiTabItem)
        } catch {
            RuntimeDiagnostics.emit("SumiDragItem encoding failed: \(error)")
        }
        item.setString(tabId.uuidString, forType: .string)
        return item
    }

    static func fromPasteboard(_ pasteboard: NSPasteboard) -> SumiDragItem? {
        guard let data = pasteboard.data(forType: .sumiTabItem) else { return nil }
        return try? JSONDecoder().decode(SumiDragItem.self, from: data)
    }
}
