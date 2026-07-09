//
//  ProfilePartition.swift
//  SumiDomain
//
//  Foundation-only identity for a browsing profile partition.
//  Icon storage matches runtime Profile (emoji String via SumiProfileIcon helpers).
//

import Foundation

public struct ProfilePartition: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    /// Emoji icon string; empty means default profile dot (`SumiProfileIcon.defaultIcon`).
    public var icon: String
    public var isEphemeral: Bool
    public var createdAt: Date?
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = SumiProfileIcon.defaultIcon,
        isEphemeral: Bool = false,
        createdAt: Date? = nil,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = SumiProfileIcon.storedValue(icon)
        self.isEphemeral = isEphemeral
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}
