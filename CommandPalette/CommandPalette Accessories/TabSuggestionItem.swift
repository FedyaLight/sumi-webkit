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
    
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    
    var body: some View {
        let tokens = themeContext.tokens(settings: sumiSettings)
        
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 9) {
                ZStack {
                    tab.favicon
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(isSelected ? tokens.primaryText : tokens.secondaryText)
                        .frame(width: 14, height: 14)
                }
                .frame(width: 24, height: 24)
                .background(isSelected ? tokens.commandPaletteChipBackground : .clear)
                .clipShape(
                    RoundedRectangle(cornerRadius: 4)
                )
                SumiTabTitleLabel(
                    title: tab.name,
                    font: .systemFont(ofSize: 13, weight: .semibold),
                    textColor: isSelected ? tokens.primaryText : tokens.secondaryText,
                    animated: false
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Text("Switch to Tab")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? tokens.secondaryText : tokens.tertiaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                ZStack {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            isSelected ? tokens.primaryText : tokens.secondaryText
                        )
                        .frame(width: 16, height: 16)
                }
                .frame(width: 24, height: 24)
                .background(tokens.commandPaletteChipBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            }
        }
        .frame(maxWidth: .infinity)
    }
}
