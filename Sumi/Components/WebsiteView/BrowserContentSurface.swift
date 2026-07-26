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

extension ChromeCornerRadii {
    /// Maps the radii to SwiftUI's y-down `RectangleCornerRadii`.
    var rectangleCornerRadii: RectangleCornerRadii {
        RectangleCornerRadii(
            topLeading: topLeading,
            bottomLeading: bottomLeading,
            bottomTrailing: bottomTrailing,
            topTrailing: topTrailing
        )
    }
}

enum BrowserContentViewportVisuals {
    static let shadowOpacity: Double = 0.3
    static let shadowRadius: CGFloat = 4
    static let shadowX: CGFloat = 0
    static let shadowY: CGFloat = 0
}

struct BrowserContentSurfaceModifier: ViewModifier {
    let style: BrowserContentSurfaceStyle

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: style.backgroundColor))
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: style.geometry.contentCornerRadii.rectangleCornerRadii,
                    style: .continuous
                )
            )
            .browserContentViewportShadow()
    }
}

extension View {
    func browserContentSurface(style: BrowserContentSurfaceStyle) -> some View {
        modifier(BrowserContentSurfaceModifier(style: style))
    }

    func browserContentViewportShadow() -> some View {
        shadow(
            color: Color.black.opacity(BrowserContentViewportVisuals.shadowOpacity),
            radius: BrowserContentViewportVisuals.shadowRadius,
            x: BrowserContentViewportVisuals.shadowX,
            y: BrowserContentViewportVisuals.shadowY
        )
    }
}
