import AppKit

struct GlanceOverlayConfiguration {
    let isVisible: Bool
    let isSidebarVisible: Bool
    let sidebarWidth: CGFloat
    let sidebarPosition: SidebarPosition
    let cornerRadius: CGFloat
    let browserContentSurfaceStyle: BrowserContentSurfaceStyle
    let accentColor: NSColor
    let surfaceColor: NSColor
    let reduceMotion: Bool
}

extension GlanceOverlayConfiguration: Equatable {
    static func == (lhs: GlanceOverlayConfiguration, rhs: GlanceOverlayConfiguration) -> Bool {
        lhs.isVisible == rhs.isVisible
            && lhs.isSidebarVisible == rhs.isSidebarVisible
            && lhs.sidebarWidth == rhs.sidebarWidth
            && lhs.sidebarPosition == rhs.sidebarPosition
            && lhs.cornerRadius == rhs.cornerRadius
            && lhs.browserContentSurfaceStyle == rhs.browserContentSurfaceStyle
            && lhs.accentColor.isEqual(rhs.accentColor)
            && lhs.surfaceColor.isEqual(rhs.surfaceColor)
            && lhs.reduceMotion == rhs.reduceMotion
    }
}
