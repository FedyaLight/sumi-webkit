import SwiftUI

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
    let geometry: BrowserChromeGeometry
    let background: Color

    func body(content: Content) -> some View {
        content
            .background(background)
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: geometry.contentCornerRadii.rectangleCornerRadii,
                    style: .continuous
                )
            )
            .browserContentViewportShadow()
    }
}

extension View {
    func browserContentSurface(
        geometry: BrowserChromeGeometry,
        background: Color
    ) -> some View {
        modifier(
            BrowserContentSurfaceModifier(
                geometry: geometry,
                background: background
            )
        )
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
