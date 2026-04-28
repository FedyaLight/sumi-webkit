import Foundation
import WebKit

struct SumiWebKitDisplayCaptureRequest: Sendable {
    let id: String
    let webKitDisplayCaptureTypeRawValue: Int
    let permissionTypes: [SumiPermissionType]
    let requestingOrigin: SumiPermissionOrigin
    let frameURL: URL?
    let isMainFrame: Bool
    let withSystemAudio: Bool

    @MainActor
    init(
        id: String = UUID().uuidString,
        origin: WKSecurityOrigin,
        frame: WKFrameInfo,
        withSystemAudio: Bool
    ) {
        self.init(
            id: id,
            webKitDisplayCaptureTypeRawValue: SumiWebKitDisplayCapturePermissionDecision.screenPrompt.rawValue,
            permissionTypes: [.screenCapture],
            requestingOrigin: SumiWebKitDisplayCaptureRequest.permissionOrigin(from: origin),
            frameURL: frame.request.url,
            isMainFrame: frame.isMainFrame,
            withSystemAudio: withSystemAudio
        )
    }

    init(
        id: String = UUID().uuidString,
        webKitDisplayCaptureTypeRawValue: Int,
        permissionTypes: [SumiPermissionType],
        requestingOrigin: SumiPermissionOrigin,
        frameURL: URL?,
        isMainFrame: Bool,
        withSystemAudio: Bool
    ) {
        self.id = id
        self.webKitDisplayCaptureTypeRawValue = webKitDisplayCaptureTypeRawValue
        self.permissionTypes = permissionTypes
        self.requestingOrigin = requestingOrigin
        self.frameURL = frameURL
        self.isMainFrame = isMainFrame
        self.withSystemAudio = withSystemAudio
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
