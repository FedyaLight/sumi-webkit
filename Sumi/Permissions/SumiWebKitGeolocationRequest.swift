import Foundation
import WebKit

struct SumiWebKitGeolocationRequest: Sendable {
    let id: String
    let requestingOrigin: SumiPermissionOrigin
    let isMainFrame: Bool

    @MainActor
    init(
        id: String = UUID().uuidString,
        frame: WKFrameInfo
    ) {
        let frameInfo = SumiNavigationFrameInfo(webKitFrame: frame)
        self.init(
            id: id,
            requestingOrigin: frameInfo.url.map(SumiPermissionOrigin.init(url:))
                ?? .invalid(reason: "missing-webkit-geolocation-frame-url"),
            isMainFrame: frameInfo.isMainFrame
        )
    }

    @available(macOS 12.0, *)
    @MainActor
    init(
        id: String = UUID().uuidString,
        origin: WKSecurityOrigin,
        frame: WKFrameInfo
    ) {
        let frameInfo = SumiNavigationFrameInfo(webKitFrame: frame)
        self.init(
            id: id,
            requestingOrigin: Self.permissionOrigin(from: origin),
            isMainFrame: frameInfo.isMainFrame
        )
    }

    init(
        id: String = UUID().uuidString,
        requestingOrigin: SumiPermissionOrigin,
        isMainFrame: Bool
    ) {
        self.id = id
        self.requestingOrigin = requestingOrigin
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
    let isCurrentPage: (@MainActor @Sendable () -> Bool)?

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
        navigationOrPageGeneration: String?,
        isCurrentPage: (@MainActor @Sendable () -> Bool)? = nil
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
        self.isCurrentPage = isCurrentPage
    }
}
