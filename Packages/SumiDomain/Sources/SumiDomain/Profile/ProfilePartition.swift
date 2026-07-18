//
//  ProfilePartition.swift
//  SumiDomain
//
//  Foundation-only identity for a browsing profile partition.
//

import Foundation

public struct ProfilePartition: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var isEphemeral: Bool
    public var createdAt: Date?
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        isEphemeral: Bool = false,
        createdAt: Date? = nil,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.isEphemeral = isEphemeral
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}
