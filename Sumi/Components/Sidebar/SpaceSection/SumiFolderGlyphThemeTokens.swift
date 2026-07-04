//
//  SumiFolderGlyphThemeTokens.swift
//  Sumi
//

import SwiftUI

extension SumiFolderGlyphPalette {
    static func sidebarFolder(
        accent: Color,
        chromeColorScheme: ColorScheme,
        primaryText: Color
    ) -> SumiFolderGlyphPalette {
        let backFill: Color
        let frontFill: Color
        let stroke: Color

        switch chromeColorScheme {
        case .light:
            backFill = accent.mixed(with: .gray, amount: 0.4)
            frontFill = accent.mixed(with: .white, amount: 0.7)
            stroke = accent.mixed(with: .black, amount: 0.5)
        case .dark:
            backFill = accent.mixed(with: Color(hex: "C1C1C1"), amount: 0.4)
            frontFill = accent.mixed(with: .black, amount: 0.4)
            stroke = Color(hex: "EBEBEB").mixed(with: primaryText, amount: 0.15)
        @unknown default:
            backFill = accent.mixed(with: .gray, amount: 0.4)
            frontFill = accent.mixed(with: .white, amount: 0.7)
            stroke = accent.mixed(with: .black, amount: 0.5)
        }

        let iconForeground = stroke.mixed(with: primaryText, amount: 0.35)
        let overlayTop = Color.white.opacity(0.1)
        let overlayBottom = Color.black.opacity(0.1)

        return SumiFolderGlyphPalette(
            backFill: backFill,
            frontFill: frontFill,
            stroke: stroke,
            iconForeground: iconForeground,
            backOverlayTop: overlayTop,
            backOverlayBottom: overlayBottom,
            frontOverlayTop: overlayTop,
            frontOverlayBottom: overlayBottom
        )
    }
}
