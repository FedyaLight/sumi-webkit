//
//  ProfileEntity.swift
//  Sumi
//
//  Runtime profile model.
//

import Foundation

final class ProfileEntity {
    var id: UUID
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
