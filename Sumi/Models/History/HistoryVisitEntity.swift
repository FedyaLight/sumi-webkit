//
//  HistoryVisitEntity.swift
//  Sumi
//

import Foundation
import SwiftData

@Model
final class HistoryEntryEntity {
    #Index<HistoryEntryEntity>(
        [\.urlKey],
        [\.profileId, \.lastVisit],
        [\.profileId, \.siteDomain],
        [\.urlString]
    )

    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var urlKey: String
    var urlString: String
    var title: String
    var domain: String
    var siteDomain: String?
    var numberOfTotalVisits: Int
    var lastVisit: Date
    var profileId: UUID?

    init(
        id: UUID = UUID(),
        urlKey: String,
        urlString: String,
        title: String,
        domain: String,
        siteDomain: String?,
        numberOfTotalVisits: Int = 0,
        lastVisit: Date,
        profileId: UUID?
    ) {
        self.id = id
        self.urlKey = urlKey
        self.urlString = urlString
        self.title = title
        self.domain = domain
        self.siteDomain = siteDomain
        self.numberOfTotalVisits = numberOfTotalVisits
        self.lastVisit = lastVisit
        self.profileId = profileId
    }
}

@Model
final class HistoryVisitEntity {
    #Index<HistoryVisitEntity>(
        [\.visitedAt],
        [\.profileId, \.visitedAt],
        [\.profileId, \.entryID],
        [\.entryID, \.visitedAt],
        [\.tabId]
    )

    @Attribute(.unique) var id: UUID
    var entryID: UUID
    var visitedAt: Date
    var profileId: UUID?
    var tabId: UUID?

    init(
        id: UUID = UUID(),
        entryID: UUID,
        visitedAt: Date,
        profileId: UUID?,
        tabId: UUID?
    ) {
        self.id = id
        self.entryID = entryID
        self.visitedAt = visitedAt
        self.profileId = profileId
        self.tabId = tabId
    }
}
