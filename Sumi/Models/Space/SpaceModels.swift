//
//  SpaceModels.swift
//  Sumi
//
//

import Foundation
import SwiftData

// Stores Space persistence, including workspace theme configuration.

@Model
final class SpaceEntity {
    #Index<SpaceEntity>([\.profileId])

    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var index: Int
    var workspaceThemeData: Data?
    var profileId: UUID?

    init(
        id: UUID,
        name: String,
        icon: String,
        index: Int,
        workspaceThemeData: Data? = nil,
        profileId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.index = index
        self.workspaceThemeData = workspaceThemeData
        self.profileId = profileId
    }
}
