import SwiftUI

struct DownloadProgressRing: View {
    let progress: Double?
    var size: CGFloat = 28

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var shouldAnimateIndeterminate: Bool {
        !reduceMotion && !sumiSettings.shouldReduceChromeMotion
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
                    .rotationEffect(.degrees(shouldAnimateIndeterminate ? rotation : 0))
                    .onAppear(perform: startIndeterminateAnimationIfNeeded)
                    .onChange(of: shouldAnimateIndeterminate) { _, shouldAnimate in
                        if shouldAnimate {
                            startIndeterminateAnimationIfNeeded()
                        } else {
                            resetIndeterminateRotation()
                        }
                    }
                    .onDisappear(perform: resetIndeterminateRotation)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func startIndeterminateAnimationIfNeeded() {
        guard shouldAnimateIndeterminate else {
            resetIndeterminateRotation()
            return
        }

        resetIndeterminateRotation()
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }

    private func resetIndeterminateRotation() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            rotation = 0
        }
    }
}
