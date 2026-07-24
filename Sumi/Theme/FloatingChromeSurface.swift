import SwiftUI

enum FloatingChromeSurfaceRole {
    case panel
    case elevated
    case rowHover
    case rowSelected

    func fill(tokens: ChromeThemeTokens) -> Color {
        switch self {
        case .panel:
            return tokens.floatingSurfaceBackground
        case .elevated:
            return tokens.floatingSurfaceSecondaryBackground
        case .rowHover:
            return tokens.floatingSurfaceHover
        case .rowSelected:
            return tokens.floatingSurfaceSelection
        }
    }
}

struct FloatingChromeSurfaceFill: View {
    let role: FloatingChromeSurfaceRole
    let opacity: Double

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

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
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }
}
