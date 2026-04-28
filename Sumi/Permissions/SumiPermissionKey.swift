import Foundation

struct SumiPermissionKey: Codable, Hashable, Sendable {
    let requestingOrigin: SumiPermissionOrigin
    let topOrigin: SumiPermissionOrigin
    let permissionType: SumiPermissionType
    let profilePartitionId: String
    let transientPageId: String?
    let isEphemeralProfile: Bool

    init(
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

    var persistentIdentity: String {
        [
            profilePartitionId,
            requestingOrigin.identity,
            topOrigin.identity,
            permissionType.identity,
        ].joined(separator: "|")
    }

    var displayDomain: String {
        requestingOrigin.displayDomain
    }

    static func == (lhs: SumiPermissionKey, rhs: SumiPermissionKey) -> Bool {
        lhs.persistentIdentity == rhs.persistentIdentity
            && lhs.isEphemeralProfile == rhs.isEphemeralProfile
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(persistentIdentity)
        hasher.combine(isEphemeralProfile)
    }

    static func normalizedProfilePartitionId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedTransientId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
