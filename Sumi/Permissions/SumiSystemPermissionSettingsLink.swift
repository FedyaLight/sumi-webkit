import AppKit
import Foundation

enum SumiSystemPermissionSettingsLink {
    static func url(for kind: SumiSystemPermissionKind) -> URL? {
        let value: String
        switch kind {
        case .camera:
            value = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case .microphone:
            value = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .geolocation:
            value = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        case .notifications:
            value = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        }
        return URL(string: value)
    }

    @MainActor
    @discardableResult
    static func open(for kind: SumiSystemPermissionKind) -> Bool {
        guard let url = url(for: kind) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
