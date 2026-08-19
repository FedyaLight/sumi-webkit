import AppKit
import SwiftUI

struct BrowserContentSurfaceStyle: Equatable {
    let geometry: BrowserChromeGeometry
    let backgroundColor: NSColor

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.geometry == rhs.geometry
            && lhs.backgroundColor.isEqual(rhs.backgroundColor)
    }
}

extension BrowserContentSurfaceStyle {
    @MainActor
    init(themeContext: ResolvedThemeContext, settings: SumiSettingsService) {
        self.init(
            geometry: BrowserChromeGeometry(settings: settings),
            backgroundColor: NSColor(
                themeContext.nativeSurfaceThemeContext
                    .tokens(settings: settings)
                    .windowBackground
            )
        )
    }
}

enum BrowserContentViewportVisuals {
    static let shadowOpacity: Double = 0.3
    static let shadowRadius: CGFloat = 4
    static let shadowX: CGFloat = 0
    static let shadowY: CGFloat = 0
}
