//
//  CommandPaletteSuggestionView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import SwiftUI

struct CommandPaletteSuggestionView: View {
    var favicon: SwiftUI.Image
    var text: String
    var secondaryText: String? = nil
    var isTabSuggestion: Bool = false
    var isSelected: Bool = false
    var historyURL: URL? = nil
    @State private var isHovered: Bool = false
    @State private var resolvedFavicon: SwiftUI.Image? = nil
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        let tokens = themeContext.tokens(settings: sumiSettings)
        HStack(alignment: .center,spacing: 12) {
            (resolvedFavicon ?? favicon)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(tokens.secondaryText.opacity(0.35))
            if let secondary = secondaryText, !secondary.isEmpty {
                HStack(spacing: 6) {
                    Text(text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tokens.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("-")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tokens.tertiaryText)
                    Text(secondary)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tokens.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            if isTabSuggestion {
                HStack(spacing: 6) {
                    Text("Switch to Tab")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tokens.secondaryText)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(tokens.secondaryText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
            
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .task(id: historyURL) {
            guard let url = historyURL else { return }
            await fetchFavicon(for: url)
        }
    }
    
    private var backgroundColor: Color {
        let tokens = themeContext.tokens(settings: sumiSettings)
        if isSelected {
            return tokens.commandPaletteRowSelected
        } else if isHovered {
            return tokens.commandPaletteRowHover
        } else {
            return Color.clear
        }
    }
    
    // MARK: - Favicon Fetching (for history items)
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
