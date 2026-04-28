import Foundation

enum SumiPermissionPromptStrings {
    static func title(
        permissionType: SumiPermissionType,
        displayDomain: String,
        externalAppName: String?
    ) -> String {
        let domain = normalizedDisplayDomain(displayDomain)
        switch permissionType {
        case .camera:
            return "\(domain) wants to use your camera"
        case .microphone:
            return "\(domain) wants to use your microphone"
        case .cameraAndMicrophone:
            return "\(domain) wants to use your camera and microphone"
        case .geolocation:
            return "\(domain) wants to know your location"
        case .notifications:
            return "\(domain) wants to show notifications"
        case .screenCapture:
            return "\(domain) wants to share your screen"
        case .storageAccess:
            return "\(domain) wants to use storage access"
        case .externalScheme:
            return "\(domain) wants to open \(externalAppName ?? "an external app")"
        case .popups:
            return "\(domain) wants to open a pop-up"
        case .autoplay:
            return "\(domain) wants to autoplay media"
        case .filePicker:
            return "\(domain) wants to choose files"
        }
    }

    static func detail(
        permissionType: SumiPermissionType,
        permissionTypes: [SumiPermissionType],
        externalAppName: String?
    ) -> String? {
        switch permissionType {
        case .cameraAndMicrophone:
            return "Use available cameras and microphones on this site."
        case .camera:
            return "Use available cameras on this site."
        case .microphone:
            return "Use available microphones on this site."
        case .screenCapture:
            return "Sumi controls site access before macOS or WebKit shows any screen picker."
        case .storageAccess:
            return "Allow this embedded site to access its cookies and website data."
        case .externalScheme(let scheme):
            let normalizedScheme = SumiPermissionType.normalizedExternalScheme(scheme)
            let appName = externalAppName ?? "an external app"
            return "Open \(normalizedScheme) links from this site in \(appName)."
        case .geolocation, .notifications:
            return nil
        case .popups, .autoplay, .filePicker:
            return permissionTypes.map(\.displayLabel).joined(separator: ", ")
        }
    }

    static func systemBlockedTitle(for snapshots: [SumiSystemPermissionSnapshot]) -> String {
        guard snapshots.count != 1, !snapshots.isEmpty else {
            return "\(snapshots.first?.kind.displayLabel ?? "Permission") access is blocked by macOS"
        }
        let labels = snapshots.map(\.kind.displayLabel).joined(separator: " and ")
        return "\(labels) access is blocked by macOS"
    }

    static func systemBlockedMessage(for snapshots: [SumiSystemPermissionSnapshot]) -> String {
        guard !snapshots.isEmpty else {
            return "macOS is blocking this permission. Site permission cannot override system settings."
        }
        return snapshots.map(\.reason).joined(separator: " ")
    }

    static func normalizedDisplayDomain(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Current site" : trimmed
    }
}
