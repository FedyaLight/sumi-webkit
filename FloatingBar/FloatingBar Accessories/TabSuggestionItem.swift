//
//  TabSuggestionItem.swift
//  Sumi
//
//  Created by Maciek Bagiński on 18/08/2025.
//

import SwiftUI

struct TabSuggestionItem: View {
    @ObservedObject var tab: Tab
    var isSelected: Bool = false
    var selectedForeground: Color? = nil
    var selectedChipBackground: Color? = nil
    var selectedChipForeground: Color? = nil
    
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    
    var body: some View {
        let tokens = themeContext.tokens(settings: sumiSettings)
        let foreground = isSelected ? (selectedForeground ?? tokens.primaryText) : tokens.secondaryText
        let chipBackground = isSelected ? (selectedChipBackground ?? tokens.floatingBarChipBackground) : tokens.floatingBarChipBackground
        let chipForeground = isSelected ? (selectedChipForeground ?? tokens.primaryText) : tokens.tertiaryText
        
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 9) {
                FloatingBarFaviconContainer {
                    tab.favicon
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(foreground)
                        .frame(
                            width: FloatingBarSuggestionMetrics.faviconImageSize,
                            height: FloatingBarSuggestionMetrics.faviconImageSize
                        )
                }
                SumiTabTitleLabel(
                    title: tab.name,
                    font: .systemFont(ofSize: 13, weight: .semibold),
                    textColor: foreground,
                    animated: false
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Text("Switch to Tab")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? foreground.opacity(0.86) : tokens.tertiaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                ZStack {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? chipForeground : tokens.secondaryText)
                        .frame(width: 16, height: 16)
                }
                .frame(width: 24, height: 24)
                .background(chipBackground)
                .clipShape(FloatingBarSuggestionMetrics.controlShape)

            }
        }
        .frame(maxWidth: .infinity)
    }
}
