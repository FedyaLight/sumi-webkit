import SwiftUI

// Dithered gradient rendering
import CoreGraphics

enum SpaceGradientBackgroundSurface {
    case browser
    case toolbarChrome
}

enum SpaceGradientBackgroundBase {
    case native
    case transparent
}

struct SpaceGradientViewport: Equatable {
    var origin: UnitPoint
    var size: CGSize

    static let full = SpaceGradientViewport(
        origin: .zero,
        size: CGSize(width: 1, height: 1)
    )

    func clamped() -> SpaceGradientViewport {
        let width = min(max(size.width, 0), 1)
        let height = min(max(size.height, 0), 1)
        let x = min(max(origin.x, 0), max(1 - width, 0))
        let y = min(max(origin.y, 0), max(1 - height, 0))
        return SpaceGradientViewport(
            origin: UnitPoint(x: x, y: y),
            size: CGSize(width: width, height: height)
        )
    }
}

// Renders the current space's gradient as a bottom background layer.
// Zen reference: `ZenGradientGenerator.getGradient` resolves workspace colors and opacity separately from `color-scheme`.
struct SpaceGradientBackgroundView: View {
    var surface: SpaceGradientBackgroundSurface = .browser
    var base: SpaceGradientBackgroundBase = .native
    var nativeMaterialRole: NativeChromeMaterialRole = .windowChrome
    var gradientFieldSize: CGSize? = nil
    var viewport: SpaceGradientViewport = .full

    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency

    private var chromeTokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var activeResolution: ZenWorkspaceThemeResolution {
        resolvedTheme(themeContext.workspaceTheme)
    }

    private var sourceResolution: ZenWorkspaceThemeResolution {
        resolvedTheme(themeContext.sourceWorkspaceTheme)
    }

    private var targetResolution: ZenWorkspaceThemeResolution {
        resolvedTheme(themeContext.targetWorkspaceTheme)
    }

    private var transitionProgress: Double {
        min(max(themeContext.transitionProgress, 0), 1)
    }

    private var usesResolvedTransitionLayers: Bool {
        themeContext.isInteractiveTransition
            || !themeContext.sourceWorkspaceTheme.visuallyEquals(themeContext.targetWorkspaceTheme)
    }

    @ViewBuilder
    var body: some View {
        gradientBackground
    }

    private var gradientBackground: some View {
        GeometryReader { proxy in
            let fieldSize = gradientFieldSize ?? proxy.size
            let clampedViewport = viewport.clamped()
            let fieldOffset = CGSize(
                width: fieldSize.width * clampedViewport.origin.x,
                height: fieldSize.height * clampedViewport.origin.y
            )
            ZStack {
                nativeBaseLayer

                if shouldRenderCustomTheme && usesResolvedTransitionLayers {
                    themedLayer(
                        for: gradient(from: sourceResolution),
                        intensity: themeContext.sourceCustomChromeThemeIntensity,
                        localSize: proxy.size,
                        fieldSize: fieldSize,
                        fieldOffset: fieldOffset
                    )
                        .opacity(1 - transitionProgress)
                    themedLayer(
                        for: gradient(from: targetResolution),
                        intensity: themeContext.targetCustomChromeThemeIntensity,
                        localSize: proxy.size,
                        fieldSize: fieldSize,
                        fieldOffset: fieldOffset
                    )
                        .opacity(transitionProgress)
                } else if shouldRenderCustomTheme {
                    themedLayer(
                        for: gradient(from: activeResolution),
                        intensity: themeContext.activeCustomChromeThemeIntensity,
                        localSize: proxy.size,
                        fieldSize: fieldSize,
                        fieldOffset: fieldOffset
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var nativeBaseLayer: some View {
        switch base {
        case .transparent:
            Color.clear
        case .native:
            switch surface {
            case .browser:
                chromeTokens.windowBackground
            case .toolbarChrome:
                if accessibilityReduceTransparency {
                    chromeTokens.windowBackground
                } else {
                    NativeChromeMaterialBackground(role: nativeMaterialRole)
                }
            }
        }
    }

    private var shouldRenderCustomTheme: Bool {
        themeContext.rendersCustomChromeTheme
    }

    private func themedLayer(
        for gradient: SpaceGradient,
        intensity: Double,
        localSize: CGSize,
        fieldSize: CGSize,
        fieldOffset: CGSize
    ) -> some View {
        ZStack {
            chromeTokens.windowBackground
            gradientVisualLayer(
                for: gradient,
                intensity: intensity,
                localSize: localSize,
                fieldSize: fieldSize,
                fieldOffset: fieldOffset
            )
        }
        .opacity(min(max(intensity, 0), 1))
    }

    private func gradientVisualLayer(
        for gradient: SpaceGradient,
        intensity: Double,
        localSize: CGSize,
        fieldSize: CGSize,
        fieldOffset: CGSize
    ) -> some View {
        let clampedIntensity = min(max(intensity, 0), 1)
        let effectiveNoiseOpacity = clampedIntensity < 0.08
            ? 0
            : max(0, min(1, gradient.grain * clampedIntensity))

        return ZStack {
            BarycentricGradientView(gradient: gradient)
                .opacity(max(0, min(1, gradient.opacity)))
                .frame(width: fieldSize.width, height: fieldSize.height)
                .clipped()
                .allowsHitTesting(false)
            if effectiveNoiseOpacity > 0 {
                TiledNoiseTexture(opacity: effectiveNoiseOpacity)
                    .frame(width: fieldSize.width, height: fieldSize.height)
                    .clipped()
                    .allowsHitTesting(false)
            }
        }
        .frame(width: fieldSize.width, height: fieldSize.height)
        .offset(x: -fieldOffset.width, y: -fieldOffset.height)
        .frame(width: localSize.width, height: localSize.height, alignment: .topLeading)
        .clipped()
    }

    private func resolvedTheme(_ theme: WorkspaceTheme) -> ZenWorkspaceThemeResolution {
        ZenWorkspaceThemeResolver.resolve(
            theme: theme,
            globalWindowScheme: themeContext.globalColorScheme,
            settings: sumiSettings
        )
    }

    private func gradient(from resolution: ZenWorkspaceThemeResolution) -> SpaceGradient {
        switch surface {
        case .browser:
            return resolution.backgroundGradient
        case .toolbarChrome:
            return resolution.toolbarGradient
        }
    }
}
