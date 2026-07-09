import Foundation

public struct SumiPermissionSecurityContext: Equatable, Sendable {
    public enum Surface: String, Codable, CaseIterable, Hashable, Sendable {
        case normalTab
        case glance
        case miniWindow
        case extensionPage
        case internalPage
        case unknown
    }

    public let request: SumiPermissionRequest
    public let requestingOrigin: SumiPermissionOrigin
    public let topOrigin: SumiPermissionOrigin
    public let committedURL: URL?
    public let visibleURL: URL?
    public let mainFrameURL: URL?
    public let isMainFrame: Bool
    public let isActiveTab: Bool
    public let isVisibleTab: Bool
    public let hasUserGesture: Bool?
    public let isEphemeralProfile: Bool
    public let profilePartitionId: String
    public let transientPageId: String?
    public let surface: Surface
    public let navigationOrPageGeneration: String?
    public let now: Date

    /// Prompt UI is fail-closed for non-normal surfaces.
    /// Glance, MiniWindow (and extension/internal/unknown) must never present permission
    /// prompts — even when the surface reports active/visible state.
    public var canPresentPromptUI: Bool {
        surface == .normalTab && isActiveTab && isVisibleTab
    }

    public init(
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
