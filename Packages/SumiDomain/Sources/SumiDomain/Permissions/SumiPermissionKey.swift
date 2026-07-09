import Foundation

public struct SumiPermissionKey: Codable, Hashable, Sendable {
    public let requestingOrigin: SumiPermissionOrigin
    public let topOrigin: SumiPermissionOrigin
    public let permissionType: SumiPermissionType
    public let profilePartitionId: String
    public let transientPageId: String?
    public let isEphemeralProfile: Bool

    public init(
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        permissionType: SumiPermissionType,
        profilePartitionId: String,
        transientPageId: String? = nil,
        isEphemeralProfile: Bool = false
    ) {
        self.requestingOrigin = requestingOrigin
        self.topOrigin = topOrigin
        self.permissionType = permissionType
        self.profilePartitionId = Self.normalizedProfilePartitionId(profilePartitionId)
        self.transientPageId = Self.normalizedTransientId(transientPageId)
        self.isEphemeralProfile = isEphemeralProfile
    }

    public var persistentIdentity: String {
        [
            profilePartitionId,
            requestingOrigin.identity,
            topOrigin.identity,
            permissionType.identity,
        ].joined(separator: "|")
    }

    public var displayDomain: String {
        requestingOrigin.displayDomain
    }

    public static func == (lhs: SumiPermissionKey, rhs: SumiPermissionKey) -> Bool {
        lhs.persistentIdentity == rhs.persistentIdentity
            && lhs.isEphemeralProfile == rhs.isEphemeralProfile
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(persistentIdentity)
        hasher.combine(isEphemeralProfile)
    }

    public static func normalizedProfilePartitionId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedTransientId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
