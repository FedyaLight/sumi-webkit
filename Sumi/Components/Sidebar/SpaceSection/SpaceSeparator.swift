//
//  SpaceSeparator.swift
//  Sumi
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

struct SpaceSeparator: View {
    let space: Space
    @Binding var isHovering: Bool
    let onClear: () -> Void
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isClearHovered: Bool = false

    var body: some View {
        let hasTabs = !browserManager.tabManager.tabs(in: space).isEmpty
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 100)
                .fill(isHovering ? tokens.separator.opacity(1.0) : tokens.separator.opacity(0.82))
                .frame(height: 1)
                .animation(.smooth(duration: 0.1), value: isHovering)

            if hasTabs && isHovering {
                Button(action: onClear) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text("Clear")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(foregroundColor)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Close other regular tabs in this space. If only the current tab remains, Clear closes it too.")
                .transition(.blur.animation(.smooth(duration: 0.08)))
                .onHover { state in
                    isClearHovered = state
                }
            }
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
    }
    
    var foregroundColor: Color {
        switch isClearHovered {
            case true:
                return tokens.primaryText
            default:
                return tokens.secondaryText
        }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}
 
