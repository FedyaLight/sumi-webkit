import AppKit

extension Notification.Name {
    static let sumiApplicationDidChangeEffectiveAppearance = Notification.Name(
        rawValue: "NSApplicationDidChangeEffectiveAppearanceNotification"
    )

    static let sumiWindowDidChangeEffectiveAppearance = Notification.Name(
        rawValue: "NSWindowDidChangeEffectiveAppearanceNotification"
    )

    static let sumiShouldHideCollapsedSidebarOverlay = Notification.Name(
        rawValue: "SumiShouldHideCollapsedSidebarOverlayNotification"
    )
}
