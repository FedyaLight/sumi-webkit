//
//  FindInPageChromePaint.swift
//  Sumi
//

import AppKit
import SwiftUI

/// AppKit colors for find-in-page, derived from the same `ChromeThemeTokens` recipe as the rest of chrome.
struct FindInPageChromePaint {
    var shellBackground: NSColor
    var shellBorder: NSColor
    var primaryText: NSColor
    var secondaryText: NSColor

    @MainActor
    static func resolve(tokens: ChromeThemeTokens) -> FindInPageChromePaint {
        return FindInPageChromePaint(
            shellBackground: Self.ns(tokens.floatingSurfaceBackground),
            shellBorder: Self.ns(tokens.floatingSurfaceBorder),
            primaryText: Self.ns(tokens.primaryText),
            secondaryText: Self.ns(tokens.secondaryText)
        )
    }

    private static func ns(_ color: Color) -> NSColor {
        let converted = NSColor(color)
        return converted.usingColorSpace(.displayP3)
            ?? converted.usingColorSpace(.sRGB)
            ?? .labelColor
    }
}
