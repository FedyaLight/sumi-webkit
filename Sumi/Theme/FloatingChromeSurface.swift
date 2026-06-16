import SwiftUI

enum FloatingChromeSurfaceRole {
    case panel
    case elevated
    case rowHover
    case rowSelected

    func fill(tokens: ChromeThemeTokens) -> Color {
        switch self {
        case .panel:
            return tokens.floatingBarBackground
        case .elevated:
            return tokens.floatingBarChipBackground
        case .rowHover:
            return tokens.floatingBarRowHover
        case .rowSelected:
            return tokens.floatingBarRowSelected
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
