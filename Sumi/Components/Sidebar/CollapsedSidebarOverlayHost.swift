import SwiftUI

enum CollapsedSidebarOverlayAnimation {
    static let revealDuration: TimeInterval = 0.25
    static let hideDuration: TimeInterval = 0.15

    static func animation(isRevealed: Bool) -> Animation {
        if isRevealed {
            return .spring(
                response: revealDuration,
                dampingFraction: 0.86,
                blendDuration: 0
            )
        }

        return .timingCurve(0.25, 0.1, 0.25, 1.0, duration: hideDuration)
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

    private var contentOffset: CGFloat {
        isRevealed ? 0 : hiddenOffset
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
            .offset(x: contentOffset)
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
