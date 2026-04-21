//
//  HistorySuggestionItem.swift
//  Sumi
//
//  Created by Maciek Bagiński on 18/08/2025.
//

import SwiftUI

struct HistorySuggestionItem: View {
    let entry: HistoryEntry
    var isSelected: Bool = false
    
    @State private var resolvedFavicon: SwiftUI.Image? = nil
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    
    private var colors: ColorConfig {
        let tokens = themeContext.tokens(settings: sumiSettings)
        return ColorConfig(tokens: tokens, isSelected: isSelected)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            ZStack {
                (resolvedFavicon ?? Image(systemName: "globe"))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(colors.faviconColor)
                    .frame(width: 14, height: 14)
            }
            .frame(width: 24, height: 24)
            .background(colors.faviconBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            
            HStack(spacing: 4) {
                Text(entry.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Text("-")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.urlColor)
                
                Text(entry.displayURL)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.urlColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .task(id: entry.url) {
            await fetchFavicon(for: entry.url)
        }
    }
    
    private func fetchFavicon(for url: URL) async {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")
        guard SumiFaviconResolver.cacheKey(for: url) != nil else {
            await MainActor.run { self.resolvedFavicon = defaultFavicon }
            return
        }

        guard let image = await SumiFaviconResolver.shared.image(for: url) else {
            await MainActor.run { self.resolvedFavicon = defaultFavicon }
            return
        }

        await MainActor.run {
            self.resolvedFavicon = SwiftUI.Image(nsImage: image)
        }
    }
}

// MARK: - Colors from chrome tokens (palette list uses command-palette row + chip tokens)
private struct ColorConfig {
    let tokens: ChromeThemeTokens
    let isSelected: Bool
    
    var titleColor: Color {
        isSelected ? tokens.primaryText : tokens.secondaryText
    }
    
    var urlColor: Color { tokens.tertiaryText }
    
    var faviconColor: Color {
        isSelected ? tokens.primaryText : tokens.secondaryText
    }
    
    var faviconBackground: Color {
        isSelected ? tokens.commandPaletteChipBackground : .clear
    }
}
