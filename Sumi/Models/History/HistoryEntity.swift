//
//  HistoryEntity.swift
//  Sumi
//
//  Created by Jonathan Caudill on 09/08/2025.
//

import Foundation
import SwiftData

@Model
class HistoryEntity {
    #Index<HistoryEntity>([\.url], [\.lastVisited], [\.profileId, \.lastVisited])

    @Attribute(.unique) var id: UUID
    var url: String
    var title: String
    var visitDate: Date
    var tabId: UUID?
    var visitCount: Int
    var lastVisited: Date
    var profileId: UUID?
    
    init(
        id: UUID = UUID(),
        url: String,
        title: String,
        visitDate: Date = Date(),
        tabId: UUID? = nil,
        visitCount: Int = 1,
        lastVisited: Date = Date(),
        profileId: UUID? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.visitDate = visitDate
        self.tabId = tabId
        self.visitCount = visitCount
        self.lastVisited = lastVisited
        self.profileId = profileId
    }
}
