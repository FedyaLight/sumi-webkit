//
//  ProfileEntity.swift
//  Sumi
//
//  SwiftData model for persisting Profiles.
//

import Foundation
import SwiftData

@Model
final class ProfileEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var index: Int

    init(
        id: UUID = UUID(),
        name: String = "Default Profile",
        index: Int = 0
    ) {
        self.id = id
        self.name = name
        self.index = index
    }
}
