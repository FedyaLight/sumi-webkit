import SwiftUI

enum FloatingChromeSurfaceRole {
    case panel
    case elevated
    case rowHover
    case rowSelected

    func fill(tokens: ChromeThemeTokens) -> Color {
        switch self {
        case .panel:
            return tokens.commandPaletteBackground
        case .elevated:
            return tokens.commandPaletteChipBackground
        case .rowHover:
            return tokens.commandPaletteRowHover
        case .rowSelected:
            return tokens.commandPaletteRowSelected
        }
    }
}

struct FloatingChromeSurfaceFill: View {
    let role: FloatingChromeSurfaceRole
    let opacity: Double

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    init(
        _ role: FloatingChromeSurfaceRole = .panel,
        opacity: Double = 1
    ) {
        self.role = role
        self.opacity = opacity
    }

    var body: some View {
        role.fill(tokens: tokens)
            .opacity(opacity)
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

struct FloatingChromeSurfaceModifier: ViewModifier {
    let role: FloatingChromeSurfaceRole
    let opacity: Double
    let cornerRadius: CGFloat?
    let drawsBorder: Bool
    let drawsShadow: Bool

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    init(
        role: FloatingChromeSurfaceRole = .panel,
        opacity: Double = 1,
        cornerRadius: CGFloat? = nil,
        drawsBorder: Bool = false,
        drawsShadow: Bool = false
    ) {
        self.role = role
        self.opacity = opacity
        self.cornerRadius = cornerRadius
        self.drawsBorder = drawsBorder
        self.drawsShadow = drawsShadow
    }

    func body(content: Content) -> some View {
        let radius = cornerRadius ?? 0
        content
            .background(role.fill(tokens: tokens).opacity(opacity))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if drawsBorder {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(tokens.separator.opacity(0.75), lineWidth: 1)
                }
            }
            .shadow(
                color: drawsShadow ? Color.black.opacity(0.25) : Color.clear,
                radius: drawsShadow ? 8 : 0,
                x: 0,
                y: drawsShadow ? 2 : 0
            )
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

extension View {
    func floatingChromeSurface(
        _ role: FloatingChromeSurfaceRole = .panel,
        opacity: Double = 1,
        cornerRadius: CGFloat? = nil,
        drawsBorder: Bool = false,
        drawsShadow: Bool = false
    ) -> some View {
        modifier(
            FloatingChromeSurfaceModifier(
                role: role,
                opacity: opacity,
                cornerRadius: cornerRadius,
                drawsBorder: drawsBorder,
                drawsShadow: drawsShadow
            )
        )
    }
}
