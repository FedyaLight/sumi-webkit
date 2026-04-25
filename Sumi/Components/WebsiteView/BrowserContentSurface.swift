import SwiftUI

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
            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 0)
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
}
