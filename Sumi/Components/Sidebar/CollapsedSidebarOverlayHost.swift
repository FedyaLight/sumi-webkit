import SwiftUI

private struct ZenCompactSidebarOffset: @preconcurrency AnimatableModifier {
    let hiddenOffset: CGFloat
    let usesTravel: Bool
    var revealProgress: CGFloat

    var animatableData: CGFloat {
        get { revealProgress }
        set { revealProgress = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: usesTravel ? hiddenOffset * (1 - revealProgress) : 0)
    }
}

struct CollapsedSidebarOverlayHost: View {
    @ObservedObject var browserManager: BrowserManager
    var windowState: BrowserWindowState
    var windowRegistry: WindowRegistry
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var chromeBackgroundResolvedThemeContext: ResolvedThemeContext
    var windowChromeSize: CGSize
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
        let mode = SidebarMotionPolicy.currentMode(reduceMotion: reduceMotion)
        if isHostRequested {
            ZStack {
                SidebarColumnRepresentable(
                    browserManager: browserManager,
                    windowState: windowState,
                    windowRegistry: windowRegistry,
                    sumiSettings: sumiSettings,
                    resolvedThemeContext: resolvedThemeContext,
                    chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext,
                    windowChromeSize: windowChromeSize,
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
                usesTravel: SidebarMotionPolicy.overlayUsesTravel(for: mode),
                revealProgress: isRevealed ? 1 : 0
            ))
            .opacity(isRevealed || SidebarMotionPolicy.overlayUsesTravel(for: mode) ? 1 : 0)
            .allowsHitTesting(isRevealed)
            .clipped()
            .alwaysArrowCursor()
            .accessibilityHidden(!isRevealed)
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}
