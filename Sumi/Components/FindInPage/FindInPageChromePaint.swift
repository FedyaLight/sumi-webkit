//
//  FindInPageChromePaint.swift
//  Sumi
//

import AppKit
import SwiftUI

/// AppKit colors for find-in-page, derived from the same `ChromeThemeTokens` recipe as the rest of chrome.
struct FindInPageChromePaint {
    /// Outer strip behind the inner focus ring.
    var shellBackground: NSColor
    var fieldUnfocused: NSColor
    var fieldFocused: NSColor
    var accentStroke: NSColor
    var accentShadow: NSColor
    var primaryText: NSColor
    var secondaryText: NSColor

    @MainActor
    static func resolve(tokens: ChromeThemeTokens) -> FindInPageChromePaint {
        let shell = tokens.floatingBarBackground
        let fieldIdle = shell.overlaying(tokens.fieldBackground)
        let fieldActive = shell.overlaying(tokens.fieldBackgroundHover)
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
