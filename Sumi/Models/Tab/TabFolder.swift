//
//  TabFolder.swift
//  Sumi
//
//

import AppKit
import Foundation
import Observation

struct TabFolderPlacement: Equatable {
    let spaceID: UUID
    let parentFolderID: UUID?
    let index: Int
}

@MainActor
@Observable
public class TabFolder: NSObject, Identifiable {
    public let id: UUID
    var name: String
    @ObservationIgnored private var placement: TabFolderPlacement
    var isOpen: Bool = false
    var isLiveFolder: Bool
    var icon: String = ""
    var color: NSColor

    var spaceId: UUID { placement.spaceID }
    var parentFolderId: UUID? { placement.parentFolderID }
    var index: Int { placement.index }

    init(
        id: UUID = UUID(),
        name: String,
        spaceId: UUID,
        parentFolderId: UUID? = nil,
        isLiveFolder: Bool = false,
        icon: String = "",
        color: NSColor = .controlAccentColor,
        index: Int = 0
    ) {
        self.id = id
        self.name = name
        self.isLiveFolder = isLiveFolder
        placement = TabFolderPlacement(
            spaceID: spaceId,
            parentFolderID: parentFolderId,
            index: index
        )
        self.icon = SumiZenFolderIconCatalog.normalizedFolderIconValue(icon)
        self.color = color
        super.init()
    }

    func installPlacement(_ value: TabFolderPlacement) {
        placement = value
    }

    var placementSnapshot: TabFolderPlacement { placement }
}
