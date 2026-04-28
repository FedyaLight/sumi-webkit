import Foundation

struct SumiPermissionRequest: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let tabId: String?
    let pageId: String?
    let frameId: String?
    let requestingOrigin: SumiPermissionOrigin
    let topOrigin: SumiPermissionOrigin
    let displayDomain: String
    let permissionTypes: [SumiPermissionType]
    let hasUserGesture: Bool
    let requestedAt: Date
    let isEphemeralProfile: Bool
    let profilePartitionId: String

    init(
        id: String = UUID().uuidString,
        tabId: String? = nil,
        pageId: String? = nil,
        frameId: String? = nil,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        displayDomain: String? = nil,
        permissionTypes: [SumiPermissionType],
        hasUserGesture: Bool = false,
        requestedAt: Date = Date(),
        isEphemeralProfile: Bool = false,
        profilePartitionId: String
    ) {
        self.id = id
        self.tabId = Self.normalizedOptionalId(tabId)
        self.pageId = Self.normalizedOptionalId(pageId)
        self.frameId = Self.normalizedOptionalId(frameId)
        self.requestingOrigin = requestingOrigin
        self.topOrigin = topOrigin
        self.displayDomain = Self.normalizedDisplayDomain(displayDomain ?? requestingOrigin.displayDomain)
        self.permissionTypes = permissionTypes
        self.hasUserGesture = hasUserGesture
        self.requestedAt = requestedAt
        self.isEphemeralProfile = isEphemeralProfile
        self.profilePartitionId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
    }

    var pageBucketId: String {
        pageId ?? tabId ?? "global"
    }

    var queuePersistentIdentity: String {
        let permissionIdentity = permissionTypes
            .map(\.identity)
            .sorted()
            .joined(separator: ",")
        return [
            profilePartitionId,
            requestingOrigin.identity,
            topOrigin.identity,
            permissionIdentity,
        ].joined(separator: "|")
    }

    func key(for permissionType: SumiPermissionType) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            permissionType: permissionType,
            profilePartitionId: profilePartitionId,
            transientPageId: pageId ?? tabId,
            isEphemeralProfile: isEphemeralProfile
        )
    }

    private static func normalizedOptionalId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedDisplayDomain(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Origin" : trimmed
    }
}
