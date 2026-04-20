//
//  SidebarMenuTab.swift
//  Sumi
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import SwiftUI

struct SidebarMenuTab: View {
    var image: String
    var activeImage: String
    var title: String
    var isActive: Bool = true
    let action: () -> Void
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovering: Bool = false
    @State private var shouldWiggle: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isActive ? activeImage : image)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.wiggle, value: shouldWiggle)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .background(backgroundColor)
        .animation(.linear(duration: 0.1), value: isHovering)
        .animation(.linear(duration: 0.2), value: isActive)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(
            color: isActive ? tokens.sidebarSelectionShadow : .clear,
            radius: isActive ? 2 : 0,
            y: isActive ? 1 : 0
        )
        .onHover { state in
            isHovering = state
        }
        .onTapGesture {
            action()
            shouldWiggle.toggle()
        }
    }

    private var iconColor: Color {
        isActive ? tokens.primaryText : tokens.secondaryText
    }

    private var textColor: Color {
        isActive ? tokens.primaryText : tokens.secondaryText
    }

    private var backgroundColor: Color {
        if isActive {
            return tokens.sidebarRowActive
        }
        if isHovering {
            return tokens.sidebarRowHover
        }
        return .clear
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}
