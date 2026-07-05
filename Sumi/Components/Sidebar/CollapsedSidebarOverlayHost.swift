import Combine
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
    var browserContext: SidebarBrowserContext
    var updaterService: SumiUpdaterService
    var hostActions: SidebarHostActions
    var structuralInvalidation: AnyPublisher<Void, Never>
    var windowState: BrowserWindowState
    var windowRegistry: WindowRegistry
    var sumiSettings: SumiSettingsService
    var nowPlayingController: SumiNativeNowPlayingController
    var resolvedThemeContext: ResolvedThemeContext
    var chromeBackgroundResolvedThemeContext: ResolvedThemeContext
    var windowChromeSize: CGSize
    var sidebarDragState: SidebarDragState
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
        let mode = SidebarMotionPolicy.currentMode(
            reduceMotion: reduceMotion,
            energySaverReducesMotion: sumiSettings.shouldReduceChromeMotion
        )
        let overlayUsesTravel = SidebarMotionPolicy.overlayUsesTravel(for: mode)
        let collapsedShadowAnimationDuration = overlayUsesTravel
            ? SidebarMotionPolicy.overlayAnimationDuration(for: mode)
            : 0
        if isHostRequested {
            ZStack {
                SidebarColumnRepresentable(
                    browserContext: browserContext,
                    updaterService: updaterService,
                    hostActions: hostActions,
                    structuralInvalidation: structuralInvalidation,
                    windowState: windowState,
                    windowRegistry: windowRegistry,
                    sumiSettings: sumiSettings,
                    nowPlayingController: nowPlayingController,
                    resolvedThemeContext: resolvedThemeContext,
                    chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext,
                    windowChromeSize: windowChromeSize,
                    sidebarDragState: sidebarDragState,
                    presentationContext: presentationContext,
                    collapsedShadowAnimationDuration: collapsedShadowAnimationDuration
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
                usesTravel: overlayUsesTravel,
                revealProgress: isRevealed ? 1 : 0
            ))
            .opacity(isRevealed || overlayUsesTravel ? 1 : 0)
            .allowsHitTesting(isRevealed)
            .alwaysArrowCursor()
            .accessibilityHidden(!isRevealed)
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}
