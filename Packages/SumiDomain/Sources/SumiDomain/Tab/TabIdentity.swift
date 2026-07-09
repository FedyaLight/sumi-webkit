//
//  TabIdentity.swift
//  SumiDomain
//
//  Foundation-only tab identity snapshot for persistence / cross-layer handoff.
//

import Foundation

public struct TabIdentity: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var url: String?
    public var title: String?
    public var spaceId: UUID?
    public var profilePartitionId: UUID?
    public var isPinned: Bool
    public var folderId: UUID?

    public init(
        id: UUID = UUID(),
        url: String? = nil,
        title: String? = nil,
        spaceId: UUID? = nil,
        profilePartitionId: UUID? = nil,
        isPinned: Bool = false,
        folderId: UUID? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.spaceId = spaceId
        self.profilePartitionId = profilePartitionId
        self.isPinned = isPinned
        self.folderId = folderId
    }
}
