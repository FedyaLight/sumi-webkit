//
//  GenericSuggestionItem.swift
//  Sumi
//
//  Created by Maciek Bagiński on 18/08/2025.
//

import SwiftUI

struct GenericSuggestionItem: View {
    let icon: Image
    let text: String
    var isSelected: Bool = false
    
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        let tokens = themeContext.tokens(settings: sumiSettings)
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(isSelected ? tokens.primaryText : tokens.secondaryText)
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? tokens.primaryText : tokens.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
