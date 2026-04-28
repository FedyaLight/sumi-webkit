import Foundation
import WebKit

struct SumiWebKitGeolocationRequest: Sendable {
    let id: String
    let requestingOrigin: SumiPermissionOrigin
    let frameURL: URL?
    let isMainFrame: Bool

    @MainActor
    init(
        id: String = UUID().uuidString,
        frame: WKFrameInfo
    ) {
        let frameURL = frame.request.url
        self.init(
            id: id,
            requestingOrigin: frameURL.map(SumiPermissionOrigin.init(url:))
                ?? .invalid(reason: "missing-webkit-geolocation-frame-url"),
            frameURL: frameURL,
            isMainFrame: frame.isMainFrame
        )
    }

    @available(macOS 12.0, *)
    @MainActor
    init(
        id: String = UUID().uuidString,
        origin: WKSecurityOrigin,
        frame: WKFrameInfo
    ) {
        self.init(
            id: id,
            requestingOrigin: Self.permissionOrigin(from: origin),
            frameURL: frame.request.url,
            isMainFrame: frame.isMainFrame
        )
    }

    init(
        id: String = UUID().uuidString,
        requestingOrigin: SumiPermissionOrigin,
        frameURL: URL?,
        isMainFrame: Bool
    ) {
        self.id = id
        self.requestingOrigin = requestingOrigin
        self.frameURL = frameURL
        self.isMainFrame = isMainFrame
    }

    @MainActor
    private static func permissionOrigin(from origin: WKSecurityOrigin) -> SumiPermissionOrigin {
        let scheme = origin.`protocol`.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = origin.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.isEmpty, !host.isEmpty else {
            return .invalid(reason: "missing-webkit-geolocation-security-origin")
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if origin.port > 0 {
            components.port = origin.port
        }

        guard let url = components.url else {
            return .invalid(reason: "malformed-webkit-geolocation-security-origin")
        }
        return SumiPermissionOrigin(url: url)
    }
}

struct SumiWebKitGeolocationTabContext: Sendable {
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
        self.tabId = tabId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pageId = pageId.trimmingCharacters(in: .whitespacesAndNewlines)
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
