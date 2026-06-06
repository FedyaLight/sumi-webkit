import SwiftUI

struct TransparencySlider: View {
    @Binding var gradientTheme: WorkspaceGradientTheme
    @EnvironmentObject private var gradientColorManager: WorkspaceThemeEditorPreview

    var body: some View {
        Slider(
            value: Binding(
                get: { gradientTheme.opacity },
                set: { newValue in
                    var updated = gradientTheme
                    updated.updateOpacity(newValue)
                    gradientTheme = updated
                    gradientColorManager.setImmediate(updated.renderGradient)
                }
            ),
            in: WorkspaceGradientTheme.minimumOpacity...WorkspaceGradientTheme.maximumOpacity
        )
        .accessibilityLabel("Chrome theme intensity")
        .padding(.horizontal, 20) // Makes the slider shorter and keeps it centered
        .frame(height: 96) // Align with the height of the adjacent GrainDial
    }
}
