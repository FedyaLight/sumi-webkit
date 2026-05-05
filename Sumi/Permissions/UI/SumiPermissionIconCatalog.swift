import Foundation

struct SumiPermissionIconDescriptor: Equatable, Sendable {
    let chromeIconName: String?
    let fallbackSystemName: String
}

enum SumiPermissionIconCatalog {
    static let generic = SumiPermissionIconDescriptor(
        chromeIconName: nil,
        fallbackSystemName: "hand.raised"
    )

    static func icon(
        for permissionType: SumiPermissionType?,
        visualStyle: SumiPermissionIndicatorVisualStyle = .neutral
    ) -> SumiPermissionIconDescriptor {
        guard let permissionType else { return generic }

        switch permissionType {
        case .camera:
            return SumiPermissionIconDescriptor(
                chromeIconName: visualStyle == .active ? "camera-fill" : "camera",
                fallbackSystemName: visualStyle == .active ? "camera.fill" : "camera"
            )
        case .microphone:
            return SumiPermissionIconDescriptor(
                chromeIconName: visualStyle == .active ? "microphone-fill" : "microphone",
                fallbackSystemName: visualStyle == .active ? "mic.fill" : "mic"
            )
        case .cameraAndMicrophone:
            return SumiPermissionIconDescriptor(
                chromeIconName: "permissions-fill",
                fallbackSystemName: visualStyle == .active ? "video.fill" : "video"
            )
        case .geolocation:
            return SumiPermissionIconDescriptor(
                chromeIconName: visualStyle == .active ? "location-solid" : "location",
                fallbackSystemName: visualStyle == .active ? "location.fill" : "location"
            )
        case .notifications:
            return SumiPermissionIconDescriptor(
                chromeIconName: visualStyle == .blocked || visualStyle == .systemWarning
                    ? "desktop-notification-blocked"
                    : "desktop-notification",
                fallbackSystemName: visualStyle == .blocked || visualStyle == .systemWarning
                    ? "bell.slash"
                    : "bell"
            )
        case .screenCapture:
            return SumiPermissionIconDescriptor(
                chromeIconName: visualStyle == .blocked || visualStyle == .systemWarning
                    ? "screen-blocked"
                    : "screen",
                fallbackSystemName: "display"
            )
        case .popups:
            return SumiPermissionIconDescriptor(
                chromeIconName: visualStyle == .blocked ? "popup-fill" : "popup",
                fallbackSystemName: "rectangle.on.rectangle"
            )
        case .externalScheme:
            return SumiPermissionIconDescriptor(
                chromeIconName: "open",
                fallbackSystemName: "arrow.up.forward.square"
            )
        case .autoplay:
            return SumiPermissionIconDescriptor(
                chromeIconName: visualStyle == .reloadRequired
                    ? "autoplay-media-blocked"
                    : "autoplay-media",
                fallbackSystemName: visualStyle == .reloadRequired ? "arrow.clockwise" : "play.rectangle"
            )
        case .storageAccess:
            return SumiPermissionIconDescriptor(
                chromeIconName: visualStyle == .blocked
                    ? "persistent-storage-blocked"
                    : "cookies-fill",
                fallbackSystemName: visualStyle == .blocked ? "externaldrive.badge.xmark" : "externaldrive"
            )
        case .filePicker:
            return SumiPermissionIconDescriptor(
                chromeIconName: nil,
                fallbackSystemName: "doc.badge.plus"
            )
        }
    }
}
