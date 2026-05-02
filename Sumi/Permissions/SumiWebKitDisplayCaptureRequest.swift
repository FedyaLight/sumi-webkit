import Foundation
import Navigation
import WebKit

struct SumiWebKitDisplayCaptureRequest: Sendable {
    let id: String
    let permissionTypes: [SumiPermissionType]
    let requestingOrigin: SumiPermissionOrigin
    let isMainFrame: Bool

    @MainActor
    init(
        id: String = UUID().uuidString,
        origin: WKSecurityOrigin,
        frame: WKFrameInfo
    ) {
        self.init(
            id: id,
            permissionTypes: [.screenCapture],
            requestingOrigin: SumiWebKitDisplayCaptureRequest.permissionOrigin(from: origin),
            isMainFrame: frame.isMainFrame
        )
    }

    init(
        id: String = UUID().uuidString,
        permissionTypes: [SumiPermissionType],
        requestingOrigin: SumiPermissionOrigin,
        isMainFrame: Bool
    ) {
        self.id = id
        self.permissionTypes = permissionTypes
        self.requestingOrigin = requestingOrigin
        self.isMainFrame = isMainFrame
    }

    @MainActor
    private static func permissionOrigin(from origin: WKSecurityOrigin) -> SumiPermissionOrigin {
        let scheme = origin.`protocol`.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = origin.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.isEmpty, !host.isEmpty else {
            return .invalid(reason: "missing-webkit-security-origin")
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if origin.port > 0 {
            components.port = origin.port
        }

        guard let url = components.url else {
            return .invalid(reason: "malformed-webkit-security-origin")
        }
        return SumiPermissionOrigin(url: url)
    }
}

struct SumiWebKitLegacyCaptureDevices: OptionSet, Sendable {
    let rawValue: UInt

    static let microphone = SumiWebKitLegacyCaptureDevices(rawValue: 1 << 0)
    static let camera = SumiWebKitLegacyCaptureDevices(rawValue: 1 << 1)
    static let display = SumiWebKitLegacyCaptureDevices(rawValue: 1 << 2)
}
