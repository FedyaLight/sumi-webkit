//
//  SpaceModels.swift
//  Sumi
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import Foundation
import SwiftData
import SwiftUI

// Stores Space persistence, including gradient configuration

@Model
final class SpaceEntity {
    #Index<SpaceEntity>([\.profileId])

    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var index: Int
    var gradientData: Data = SpaceGradient.default.encoded ?? Data()
    var workspaceThemeData: Data?
    // Added in later schema: optional to enable lightweight migration without data loss
    // SwiftData should migrate automatically for new optional properties.
    // If issues arise in the wild, consider introducing an explicit model version and migration plan.
    var profileId: UUID?

    init(
        id: UUID,
        name: String,
        icon: String,
        index: Int,
        gradientData: Data = SpaceGradient.default.encoded ?? Data(),
        workspaceThemeData: Data? = nil,
        profileId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.index = index
        self.gradientData = gradientData
        self.workspaceThemeData = workspaceThemeData
        self.profileId = profileId
    }
}
