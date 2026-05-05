import Foundation

struct SumiPermissionSecurityContext: Equatable, Sendable {
    enum Surface: String, Codable, CaseIterable, Hashable, Sendable {
        case normalTab
        case miniWindow
        case glance
        case extensionPage
        case internalPage
        case unknown
    }

    let request: SumiPermissionRequest
    let requestingOrigin: SumiPermissionOrigin
    let topOrigin: SumiPermissionOrigin
    let committedURL: URL?
    let visibleURL: URL?
    let mainFrameURL: URL?
    let isMainFrame: Bool
    let isActiveTab: Bool
    let isVisibleTab: Bool
    let hasUserGesture: Bool?
    let isEphemeralProfile: Bool
    let profilePartitionId: String
    let transientPageId: String?
    let surface: Surface
    let navigationOrPageGeneration: String?
    let now: Date

    init(
        request: SumiPermissionRequest,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        committedURL: URL?,
        visibleURL: URL?,
        mainFrameURL: URL?,
        isMainFrame: Bool,
        isActiveTab: Bool,
        isVisibleTab: Bool,
        hasUserGesture: Bool?,
        isEphemeralProfile: Bool,
        profilePartitionId: String,
        transientPageId: String?,
        surface: Surface,
        navigationOrPageGeneration: String?,
        now: Date
    ) {
        self.request = request
        self.requestingOrigin = requestingOrigin
        self.topOrigin = topOrigin
        self.committedURL = committedURL
        self.visibleURL = visibleURL
        self.mainFrameURL = mainFrameURL
        self.isMainFrame = isMainFrame
        self.isActiveTab = isActiveTab
        self.isVisibleTab = isVisibleTab
        self.hasUserGesture = hasUserGesture
        self.isEphemeralProfile = isEphemeralProfile
        self.profilePartitionId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        self.transientPageId = Self.normalizedOptionalId(transientPageId)
        self.surface = surface
        self.navigationOrPageGeneration = Self.normalizedOptionalId(navigationOrPageGeneration)
        self.now = now
    }

    private static func normalizedOptionalId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
