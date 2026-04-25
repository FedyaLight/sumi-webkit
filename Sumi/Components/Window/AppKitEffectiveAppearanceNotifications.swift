import AppKit

extension Notification.Name {
    static let sumiApplicationDidChangeEffectiveAppearance = Notification.Name(
        rawValue: "NSApplicationDidChangeEffectiveAppearanceNotification"
    )

    static let sumiWindowDidChangeEffectiveAppearance = Notification.Name(
        rawValue: "NSWindowDidChangeEffectiveAppearanceNotification"
    )
}
