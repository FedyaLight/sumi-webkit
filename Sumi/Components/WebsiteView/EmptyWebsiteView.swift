//
//  EmptyWebsiteView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct EmptyWebsiteView: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var chromeGeometry: BrowserChromeGeometry {
        BrowserChromeGeometry(settings: sumiSettings)
    }

    private var backgroundColor: Color {
        themeContext.tokens(settings: sumiSettings).windowBackground
    }

    var body: some View {
        backgroundColor
            .opacity(0.2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: chromeGeometry.contentRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 0)
            .accessibilityHidden(true)
    }
}
