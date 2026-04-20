import SwiftUI

struct SidebarInsertionGuide: View {
    static let visualCenterY: CGFloat = 3

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(tokens.dropGuide)
                .frame(width: 4, height: 4)

            Capsule(style: .continuous)
                .fill(tokens.dropGuide)
                .frame(maxWidth: .infinity)
                .frame(height: 2)
        }
            .frame(maxWidth: .infinity)
            .frame(height: 6)
            .accessibilityHidden(true)
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

// MARK: - Empty drop zone outlines (dash until hover shows real preview)

/// Dashed tile outline for an empty Essentials row during drag — not a content preview.
struct SidebarEssentialsEmptyDropDashPlaceholder: View {
    let size: CGSize

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        let corner = sumiSettings.resolvedCornerRadius(10)
        let tokens = themeContext.tokens(settings: sumiSettings)
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(tokens.dropGuideBackground.opacity(0.55))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    tokens.dropGuide.opacity(0.92),
                    style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [5, 4])
                )
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// Dashed strip for an empty space-pinned area during drag — not a row preview.
struct SidebarPinnedEmptyDropDashPlaceholder: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        let tokens = themeContext.tokens(settings: sumiSettings)
        let corner: CGFloat = 6
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(tokens.dropGuideBackground.opacity(0.45))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    tokens.dropGuide.opacity(0.92),
                    style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [7, 5])
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(SidebarRowLayout.rowHeight - 10, 20))
        .padding(.vertical, 5)
        .accessibilityHidden(true)
    }
}
