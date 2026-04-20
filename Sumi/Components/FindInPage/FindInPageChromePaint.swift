//
//  FindInPageChromePaint.swift
//  Sumi
//

import AppKit
import SwiftUI

/// AppKit colors for find-in-page, derived from the same `ChromeThemeTokens` recipe as the rest of chrome.
struct FindInPageChromePaint {
    /// Outer strip behind the inner focus ring (slightly tied to toolbar + field).
    var shellBackground: NSColor
    var fieldUnfocused: NSColor
    var fieldFocused: NSColor
    var accentStroke: NSColor
    var accentShadow: NSColor
    var primaryText: NSColor
    var secondaryText: NSColor

    @MainActor
    static func resolve(tokens: ChromeThemeTokens) -> FindInPageChromePaint {
        // Light mixing keeps the bar visually consistent with URL bar / chrome fields without cloning a single flat token.
        let shell = tokens.toolbarBackground.mixed(with: tokens.fieldBackground, amount: 0.30)
        let fieldIdle = tokens.fieldBackground.mixed(with: tokens.toolbarBackground, amount: 0.18)
        let fieldActive = tokens.fieldBackgroundHover.mixed(with: tokens.toolbarBackground, amount: 0.12)
        let accent = tokens.accent

        return FindInPageChromePaint(
            shellBackground: Self.ns(shell),
            fieldUnfocused: Self.ns(fieldIdle),
            fieldFocused: Self.ns(fieldActive),
            accentStroke: Self.ns(accent),
            accentShadow: Self.ns(accent).withAlphaComponent(0.34),
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
