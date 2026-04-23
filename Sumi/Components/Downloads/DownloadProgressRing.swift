import SwiftUI

struct DownloadProgressRing: View {
    let progress: Double?
    var size: CGFloat = 28

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var rotation: Double = 0

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tokens.primaryText.opacity(0.18), lineWidth: 2)

            if let progress, progress >= 0 {
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(
                        tokens.primaryText,
                        style: StrokeStyle(lineWidth: 2.25, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.18), value: progress)
            } else {
                Circle()
                    .trim(from: 0.08, to: 0.36)
                    .stroke(
                        tokens.primaryText,
                        style: StrokeStyle(lineWidth: 2.25, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
