import Foundation

struct SumiPermissionSecurityContext: Equatable, Sendable {
    enum Surface: String, Codable, CaseIterable, Hashable, Sendable {
        case normalTab
        case miniWindow
        case peek
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
        requestingOrigin: SumiPermissionOrigin? = nil,
        topOrigin: SumiPermissionOrigin? = nil,
        committedURL: URL? = nil,
        visibleURL: URL? = nil,
        mainFrameURL: URL? = nil,
        isMainFrame: Bool = true,
        isActiveTab: Bool = true,
        isVisibleTab: Bool = true,
        hasUserGesture: Bool? = nil,
        isEphemeralProfile: Bool? = nil,
        profilePartitionId: String? = nil,
        transientPageId: String? = nil,
        surface: Surface = .normalTab,
        navigationOrPageGeneration: String? = nil,
        now: Date = Date()
    ) {
        self.request = request
        self.requestingOrigin = requestingOrigin ?? request.requestingOrigin
        self.topOrigin = topOrigin ?? request.topOrigin
        self.committedURL = committedURL
        self.visibleURL = visibleURL
        self.mainFrameURL = mainFrameURL
        self.isMainFrame = isMainFrame
        self.isActiveTab = isActiveTab
        self.isVisibleTab = isVisibleTab
        self.hasUserGesture = hasUserGesture ?? request.hasUserGesture
        self.isEphemeralProfile = isEphemeralProfile ?? request.isEphemeralProfile
        self.profilePartitionId = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId ?? request.profilePartitionId
        )
        self.transientPageId = Self.normalizedOptionalId(
            transientPageId ?? request.pageId ?? request.tabId
        )
        self.surface = surface
        self.navigationOrPageGeneration = Self.normalizedOptionalId(navigationOrPageGeneration)
        self.now = now
    }

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
