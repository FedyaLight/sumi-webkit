//
//  URLBarCompactButtonStyle.swift
//  Sumi
//
//  Compact rounded button style used in URL bar popovers and hub sections.
//

import SwiftUI

struct URLBarCompactButtonStyle: ButtonStyle {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let width: CGFloat?
    let minWidth: CGFloat?

    init(width: CGFloat? = nil, minWidth: CGFloat? = nil) {
        self.width = width
        self.minWidth = minWidth
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(tokens.primaryText)
            .padding(.horizontal, width == nil ? 12 : 0)
            .frame(width: width, height: 28)
            .frame(minWidth: minWidth, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        ThemeChromeRecipeBuilder.urlBarPillFieldBackground(
            tokens: tokens,
            isPressed: isPressed,
            isHovering: isHovering,
            isEnabled: isEnabled
        )
    }
}
