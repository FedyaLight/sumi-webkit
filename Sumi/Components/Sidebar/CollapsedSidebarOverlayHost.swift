import SwiftUI

enum CollapsedSidebarOverlayAnimation {
    static let revealDuration: TimeInterval = 0.25
    static let hideDuration: TimeInterval = 0.25
    static let dockedLayoutDuration: TimeInterval = 0.20
    static let dockedLayoutUnmountDelay: TimeInterval = 0.26

    static func animation(isRevealed: Bool) -> Animation {
        if isRevealed {
            return .linear(duration: revealDuration)
        }

        return .linear(duration: hideDuration)
    }

    static func dockedLayoutAnimation(isShowing: Bool) -> Animation {
        .timingCurve(
            isShowing ? 0.0 : 0.42,
            0.0,
            isShowing ? 0.58 : 1.0,
            1.0,
            duration: dockedLayoutDuration
        )
    }
}

private enum ZenCompactSidebarTiming {
    private static let samples: [(CGFloat, CGFloat)] = [
        (0.00, 0.000000), (0.01, 0.002748), (0.02, 0.010544), (0.03, 0.022757),
        (0.04, 0.038804), (0.05, 0.058151), (0.06, 0.080308), (0.07, 0.104828),
        (0.08, 0.131301), (0.09, 0.159358), (0.10, 0.188662), (0.11, 0.218910),
        (0.12, 0.249828), (0.13, 0.281172), (0.14, 0.312724), (0.15, 0.344288),
        (0.16, 0.375693), (0.17, 0.406790), (0.18, 0.437447), (0.19, 0.467549),
        (0.20, 0.497000), (0.21, 0.525718), (0.22, 0.553633), (0.23, 0.580688),
        (0.24, 0.606840), (0.25, 0.632052), (0.26, 0.656298), (0.27, 0.679562),
        (0.28, 0.701831), (0.29, 0.723104), (0.30, 0.743381), (0.31, 0.762670),
        (0.32, 0.780983), (0.33, 0.798335), (0.34, 0.814744), (0.35, 0.830233),
        (0.36, 0.844826), (0.37, 0.858549), (0.38, 0.871430), (0.39, 0.883498),
        (0.40, 0.894782), (0.41, 0.905314), (0.42, 0.915125), (0.43, 0.924247),
        (0.44, 0.932710), (0.45, 0.940547), (0.46, 0.947787), (0.47, 0.954463),
        (0.48, 0.960603), (0.49, 0.966239), (0.50, 0.971397), (0.51, 0.976106),
        (0.52, 0.980394), (0.53, 0.984286), (0.54, 0.987808), (0.55, 0.990984),
        (0.56, 0.993837), (0.57, 0.996390), (0.58, 0.998664), (0.59, 1.000679),
        (0.60, 1.002456), (0.61, 1.004011), (0.62, 1.005363), (0.63, 1.006528),
        (0.64, 1.007522), (0.65, 1.008359), (0.66, 1.009054), (0.67, 1.009618),
        (0.68, 1.010065), (0.69, 1.010405), (0.70, 1.010649), (0.71, 1.010808),
        (0.72, 1.010890), (0.73, 1.010904), (0.74, 1.010857), (0.75, 1.010757),
        (0.76, 1.010611), (0.77, 1.010425), (0.78, 1.010205), (0.79, 1.009955),
        (0.80, 1.009681), (0.81, 1.009387), (0.82, 1.009077), (0.83, 1.008754),
        (0.84, 1.008422), (0.85, 1.008083), (0.86, 1.007740), (0.87, 1.007396),
        (0.88, 1.007052), (0.89, 1.006710), (0.90, 1.006372), (0.91, 1.006040),
        (0.92, 1.005713), (0.93, 1.005394), (0.94, 1.005083), (0.95, 1.004782),
        (0.96, 1.004489), (0.97, 1.004207), (0.98, 1.003935), (0.99, 1.003674),
        (1.00, 1.003423),
    ]

    static func value(at progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else { return 0 }
        guard clamped < 1 else { return 1 }

        let scaled = clamped * 100
        let lowerIndex = min(max(Int(floor(scaled)), 0), samples.count - 2)
        let upperIndex = lowerIndex + 1
        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]
        let span = upper.0 - lower.0
        guard span > 0 else { return lower.1 }
        let localProgress = (clamped - lower.0) / span
        return lower.1 + (upper.1 - lower.1) * localProgress
    }
}

private struct ZenCompactSidebarOffset: @preconcurrency AnimatableModifier {
    let hiddenOffset: CGFloat
    var revealProgress: CGFloat

    var animatableData: CGFloat {
        get { revealProgress }
        set { revealProgress = newValue }
    }

    func body(content: Content) -> some View {
        let easedProgress = ZenCompactSidebarTiming.value(at: revealProgress)
        return content.offset(x: hiddenOffset * (1 - easedProgress))
    }
}

struct CollapsedSidebarOverlayHost: View {
    @ObservedObject var browserManager: BrowserManager
    var windowState: BrowserWindowState
    var windowRegistry: WindowRegistry
    var commandPalette: CommandPalette
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var chromeBackgroundResolvedThemeContext: ResolvedThemeContext
    var presentationContext: SidebarPresentationContext
    var isHostRequested: Bool

    private var isRevealed: Bool {
        presentationContext.mode == .collapsedVisible
    }

    private var hiddenOffset: CGFloat {
        presentationContext.shellEdge.isLeft
            ? -presentationContext.sidebarWidth
            : presentationContext.sidebarWidth
    }

    var body: some View {
        if isHostRequested {
            ZStack {
                SidebarColumnRepresentable(
                    browserManager: browserManager,
                    windowState: windowState,
                    windowRegistry: windowRegistry,
                    commandPalette: commandPalette,
                    sumiSettings: sumiSettings,
                    resolvedThemeContext: resolvedThemeContext,
                    chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext,
                    presentationContext: presentationContext
                )

                if isRevealed {
                    WebContentHoverShieldSensorView()
                }
            }
            .id("collapsed-sidebar-overlay-column")
            .frame(width: presentationContext.sidebarWidth)
            .frame(maxHeight: .infinity)
            .modifier(ZenCompactSidebarOffset(
                hiddenOffset: hiddenOffset,
                revealProgress: isRevealed ? 1 : 0
            ))
            .animation(
                CollapsedSidebarOverlayAnimation.animation(isRevealed: isRevealed),
                value: isRevealed
            )
            .allowsHitTesting(isRevealed)
            .clipped()
            .alwaysArrowCursor()
            .accessibilityHidden(!isRevealed)
        }
    }
}
