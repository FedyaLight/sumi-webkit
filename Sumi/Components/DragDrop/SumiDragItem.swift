//
//  SumiDragItem.swift
//  Sumi
//

import Foundation
import AppKit

extension NSPasteboard.PasteboardType {
    static let sumiSidebarDragPayload = NSPasteboard.PasteboardType("com.sumi.sidebar-drag-payload")
}

extension NSPasteboard {
    var sumiDroppedURL: URL? {
        if let urlString = string(forType: .URL) ?? string(forType: .fileURL),
           let url = URL(string: urlString) {
            return url
        }

        if let string = string(forType: .string) {
            if let url = URL(string: string), url.scheme != nil {
                return url
            }
            if string.hasPrefix("/") {
                return URL(fileURLWithPath: string)
            }
        }

        let fileURLs = readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        if let fileURL = fileURLs?.first {
            return fileURL
        }

        let urls = readObjects(
            forClasses: [NSURL.self],
            options: nil
        ) as? [URL]
        return urls?.first
    }
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

struct SidebarDragPasteboardPayload: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let item: SumiDragItem
    let sourceWindowId: UUID?
    let sourceSpaceId: UUID
    let sourceProfileId: UUID?
    let sourceContainer: TabDragManager.DragContainer
    let sourceItemId: UUID
    let sourceItemKind: SumiDragItemKind

    init(
        item: SumiDragItem,
        scope: SidebarDragScope
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.item = item
        self.sourceWindowId = scope.windowId
        self.sourceSpaceId = scope.spaceId
        self.sourceProfileId = scope.profileId
        self.sourceContainer = scope.sourceContainer
        self.sourceItemId = scope.sourceItemId
        self.sourceItemKind = scope.sourceItemKind
    }

    var scope: SidebarDragScope {
        SidebarDragScope(
            windowId: sourceWindowId,
            spaceId: sourceSpaceId,
            profileId: sourceProfileId,
            sourceContainer: sourceContainer,
            sourceItemId: sourceItemId,
            sourceItemKind: sourceItemKind
        )
    }

    static func fromPasteboard(_ pasteboard: NSPasteboard) -> SidebarDragPasteboardPayload? {
        guard let data = pasteboard.data(forType: .sumiSidebarDragPayload),
              let payload = try? JSONDecoder().decode(SidebarDragPasteboardPayload.self, from: data),
              payload.schemaVersion == currentSchemaVersion else {
            return nil
        }
        return payload
    }
}

extension SidebarDragScope {
    init(
        windowId: UUID?,
        spaceId: UUID,
        profileId: UUID?,
        sourceContainer: TabDragManager.DragContainer,
        sourceItemId: UUID,
        sourceItemKind: SumiDragItemKind
    ) {
        self.windowId = windowId
        self.spaceId = spaceId
        self.profileId = profileId
        self.sourceContainer = sourceContainer
        self.sourceItemId = sourceItemId
        self.sourceItemKind = sourceItemKind
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
    func pasteboardItem(scope: SidebarDragScope) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        do {
            let payload = SidebarDragPasteboardPayload(item: self, scope: scope)
            let data = try JSONEncoder().encode(payload)
            item.setData(data, forType: .sumiSidebarDragPayload)
        } catch {
            RuntimeDiagnostics.emit("SidebarDragPasteboardPayload encoding failed: \(error)")
        }

        item.setString(tabId.uuidString, forType: .string)
        return item
    }
}
