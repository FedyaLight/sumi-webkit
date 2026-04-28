import Foundation
import WebKit

struct SumiFilePickerPermissionRequest: Sendable {
    let id: String
    let requestingOrigin: SumiPermissionOrigin
    let frameURL: URL?
    let isMainFrame: Bool
    let allowsMultipleSelection: Bool
    let allowsDirectories: Bool
    let allowedContentTypeIdentifiers: [String]
    let allowedFileExtensions: [String]
    let userActivation: SumiPopupUserActivationState

    @MainActor
    init(
        id: String = UUID().uuidString,
        parameters: WKOpenPanelParameters,
        frame: WKFrameInfo,
        userActivation: SumiPopupUserActivationState
    ) {
        self.init(
            id: id,
            requestingOrigin: Self.permissionOrigin(from: frame.securityOrigin),
            frameURL: frame.request.url,
            isMainFrame: frame.isMainFrame,
            allowsMultipleSelection: parameters.allowsMultipleSelection,
            allowsDirectories: parameters.allowsDirectories,
            allowedContentTypeIdentifiers: [],
            allowedFileExtensions: [],
            userActivation: userActivation
        )
    }

    init(
        id: String = UUID().uuidString,
        requestingOrigin: SumiPermissionOrigin,
        frameURL: URL?,
        isMainFrame: Bool,
        allowsMultipleSelection: Bool,
        allowsDirectories: Bool,
        allowedContentTypeIdentifiers: [String] = [],
        allowedFileExtensions: [String] = [],
        userActivation: SumiPopupUserActivationState
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : id
        self.requestingOrigin = requestingOrigin
        self.frameURL = frameURL
        self.isMainFrame = isMainFrame
        self.allowsMultipleSelection = allowsMultipleSelection
        self.allowsDirectories = allowsDirectories
        self.allowedContentTypeIdentifiers = allowedContentTypeIdentifiers
        self.allowedFileExtensions = allowedFileExtensions
        self.userActivation = userActivation
    }

    var isUserActivated: Bool {
        userActivation.isUserActivated
    }

    @MainActor
    private static func permissionOrigin(from origin: WKSecurityOrigin) -> SumiPermissionOrigin {
        let scheme = origin.`protocol`.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = origin.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.isEmpty, !host.isEmpty else {
            return .invalid(reason: "missing-webkit-file-picker-security-origin")
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if origin.port > 0 {
            components.port = origin.port
        }

        guard let url = components.url else {
            return .invalid(reason: "malformed-webkit-file-picker-security-origin")
        }
        return SumiPermissionOrigin(url: url)
    }
}

struct SumiFilePickerPermissionTabContext: Sendable {
    let tabId: String
    let pageId: String
    let profilePartitionId: String
    let isEphemeralProfile: Bool
    let committedURL: URL?
    let visibleURL: URL?
    let mainFrameURL: URL?
    let isActiveTab: Bool
    let isVisibleTab: Bool
    let navigationOrPageGeneration: String?

    init(
        tabId: String,
        pageId: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        committedURL: URL?,
        visibleURL: URL?,
        mainFrameURL: URL?,
        isActiveTab: Bool,
        isVisibleTab: Bool,
        navigationOrPageGeneration: String?
    ) {
        self.tabId = tabId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.pageId = pageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.profilePartitionId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        self.isEphemeralProfile = isEphemeralProfile
        self.committedURL = committedURL
        self.visibleURL = visibleURL
        self.mainFrameURL = mainFrameURL
        self.isActiveTab = isActiveTab
        self.isVisibleTab = isVisibleTab
        self.navigationOrPageGeneration = navigationOrPageGeneration?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
