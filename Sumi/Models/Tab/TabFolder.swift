//
//  TabFolder.swift
//  Sumi
//
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
public class TabFolder: NSObject, Identifiable {
    public let id: UUID
    var name: String
    var spaceId: UUID
    var parentFolderId: UUID?
    var isOpen: Bool = false
    var icon: String = ""
    var index: Int
    var color: NSColor

    init(
        id: UUID = UUID(),
        name: String,
        spaceId: UUID,
        parentFolderId: UUID? = nil,
        icon: String = "",
        color: NSColor = .controlAccentColor,
        index: Int = 0
    ) {
        self.id = id
        self.name = name
        self.spaceId = spaceId
        self.parentFolderId = parentFolderId
        self.icon = SumiZenFolderIconCatalog.normalizedFolderIconValue(icon)
        self.color = color
        self.index = index
        super.init()
    }
}
