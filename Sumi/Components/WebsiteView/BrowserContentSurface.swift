import SwiftUI

enum BrowserContentViewportVisuals {
    static let shadowOpacity: Double = 0.3
    static let shadowRadius: CGFloat = 4
    static let shadowX: CGFloat = 0
    static let shadowY: CGFloat = 0
    static let cornerCutoutShadowOpacityMultiplier: CGFloat = 0.45
    static let cornerCutoutShadowRadiusMultiplier: CGFloat = 1.35
}

struct BrowserContentSurfaceModifier: ViewModifier {
    let geometry: BrowserChromeGeometry
    let background: Color

    func body(content: Content) -> some View {
        content
            .background(background)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: geometry.contentRadius,
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
