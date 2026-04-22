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
