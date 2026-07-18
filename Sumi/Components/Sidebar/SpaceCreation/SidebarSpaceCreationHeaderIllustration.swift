import SwiftUI

/// Static "fanned cards" header art for the space-creation panel.
/// Pure shapes and emoji: no assets, materials, or animation.
struct SidebarSpaceCreationHeaderIllustration: View {
    let tokens: ChromeThemeTokens

    private static let cardSize = CGSize(width: 44, height: 56)
    private static let cardCornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            card(emoji: "🌴")
                .rotationEffect(.degrees(-12))
                .offset(x: -26, y: 4)

            card(emoji: "📚")
                .rotationEffect(.degrees(10))
                .offset(x: 26, y: 4)

            card(emoji: "💻")
        }
        .frame(width: 120, height: 68)
        .accessibilityHidden(true)
    }

    private func card(emoji: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                .fill(.white)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                        .strokeBorder(tokens.separator.opacity(0.8), lineWidth: 1)
                }

            Text(emoji)
                .font(.system(size: 25))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .padding(5)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
    }
}
