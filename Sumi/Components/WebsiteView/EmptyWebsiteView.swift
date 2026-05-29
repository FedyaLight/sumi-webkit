//
//  EmptyWebsiteView.swift
//  Sumi
//
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
            .browserContentViewportShadow()
            .accessibilityHidden(true)
    }
}
