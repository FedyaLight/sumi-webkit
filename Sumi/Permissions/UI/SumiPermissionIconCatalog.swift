import Foundation

struct SumiPermissionIconDescriptor: Equatable, Sendable {
    let id: String
    let chromeIconName: String?
    let fallbackSystemName: String
}

enum SumiPermissionIconCatalog {
    static let generic = SumiPermissionIconDescriptor(
        id: "permissions",
        chromeIconName: "permissions",
        fallbackSystemName: "line.3.horizontal.decrease.circle"
    )

    static func icon(
        for permissionType: SumiPermissionType?,
        visualStyle: SumiPermissionIndicatorVisualStyle = .neutral
    ) -> SumiPermissionIconDescriptor {
        guard let permissionType else { return generic }

        switch permissionType {
        case .camera:
            return SumiPermissionIconDescriptor(
                id: visualStyle == .active ? "camera.active" : "camera",
                chromeIconName: visualStyle == .active ? "camera-fill" : "camera",
                fallbackSystemName: visualStyle == .active ? "camera.fill" : "camera"
            )
        case .microphone:
            return SumiPermissionIconDescriptor(
                id: visualStyle == .active ? "microphone.active" : "microphone",
                chromeIconName: visualStyle == .active ? "microphone-fill" : "microphone",
                fallbackSystemName: visualStyle == .active ? "mic.fill" : "mic"
            )
        case .cameraAndMicrophone:
            return SumiPermissionIconDescriptor(
                id: visualStyle == .active ? "camera-microphone.active" : "camera-microphone",
                chromeIconName: "permissions-fill",
                fallbackSystemName: visualStyle == .active ? "video.fill" : "video"
            )
        case .geolocation:
            return SumiPermissionIconDescriptor(
                id: visualStyle == .active ? "geolocation.active" : "geolocation",
                chromeIconName: visualStyle == .active ? "location-solid" : "location",
                fallbackSystemName: visualStyle == .active ? "location.fill" : "location"
            )
        case .notifications:
            return SumiPermissionIconDescriptor(
                id: visualStyle == .blocked || visualStyle == .systemWarning
                    ? "notifications.blocked"
                    : "notifications",
                chromeIconName: visualStyle == .blocked || visualStyle == .systemWarning
                    ? "desktop-notification-blocked"
                    : "desktop-notification",
                fallbackSystemName: visualStyle == .blocked || visualStyle == .systemWarning
                    ? "bell.slash"
                    : "bell"
            )
        case .screenCapture:
            return SumiPermissionIconDescriptor(
                id: visualStyle == .active ? "screen-capture.active" : "screen-capture",
                chromeIconName: visualStyle == .blocked || visualStyle == .systemWarning
                    ? "screen-blocked"
                    : "screen",
                fallbackSystemName: "display"
            )
        case .popups:
            return SumiPermissionIconDescriptor(
                id: "popups.blocked",
                chromeIconName: visualStyle == .blocked ? "popup-fill" : "popup",
                fallbackSystemName: "rectangle.on.rectangle"
            )
        case .externalScheme:
            return SumiPermissionIconDescriptor(
                id: "external-scheme",
                chromeIconName: "open",
                fallbackSystemName: "arrow.up.forward.square"
            )
        case .autoplay:
            return SumiPermissionIconDescriptor(
                id: visualStyle == .reloadRequired ? "autoplay.reload-required" : "autoplay",
                chromeIconName: visualStyle == .reloadRequired
                    ? "autoplay-media-blocked"
                    : "autoplay-media",
                fallbackSystemName: visualStyle == .reloadRequired ? "arrow.clockwise" : "play.rectangle"
            )
        case .storageAccess:
            return SumiPermissionIconDescriptor(
                id: visualStyle == .blocked ? "storage-access.blocked" : "storage-access",
                chromeIconName: visualStyle == .blocked
                    ? "persistent-storage-blocked"
                    : "cookies-fill",
                fallbackSystemName: visualStyle == .blocked ? "externaldrive.badge.xmark" : "externaldrive"
            )
        case .filePicker:
            return SumiPermissionIconDescriptor(
                id: "file-picker.current-event",
                chromeIconName: nil,
                fallbackSystemName: "doc.badge.plus"
            )
        }
    }

    static func documentedFallbackReason(
        for permissionType: SumiPermissionType
    ) -> String? {
        let descriptor = icon(for: permissionType)
        guard descriptor.chromeIconName == nil else { return nil }
        return "No bundled Sumi chrome icon is required; URL bar falls back to SF Symbol \(descriptor.fallbackSystemName)."
    }
}
