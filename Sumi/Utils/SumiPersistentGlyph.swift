//
//  SumiPersistentGlyph.swift
//  Sumi
//
//  Validates persisted “glyph” strings used as either emoji text or SF Symbol
//  names so UI code never asks the system symbol set for invalid names.
//

import AppKit

enum SumiPersistentGlyph {
    /// Default SF Symbol for spaces (matches `Space`’s initializer default).
    static let spaceSystemImageFallback = "square.grid.2x2"
    /// Default launcher fallback when no bitmap favicon or custom launcher icon exists.
    static let launcherSystemImageFallback = "globe"

    /// True when the string should be drawn as text (emoji / pictographic slot).
    static func presentsAsEmoji(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.unicodeScalars.allSatisfy(\.isASCII) == false else { return false }

        return trimmed.unicodeScalars.contains { scalar in
            if scalar.properties.isEmoji {
                return true
            }
            let v = scalar.value
            return (v >= 0x1F300 && v <= 0x1F9FF)
                || (v >= 0x2600 && v <= 0x26FF)
                || (v >= 0x2700 && v <= 0x27BF)
        }
    }

    static func isValidSystemSymbolName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil
    }

    /// SF Symbol name safe for `Image(systemName:)` / `Label(..., systemImage:)` (never emoji).
    static func resolvedSpaceSystemImageName(_ stored: String) -> String {
        guard !presentsAsEmoji(stored) else { return spaceSystemImageFallback }
        if isValidSystemSymbolName(stored) { return stored.trimmingCharacters(in: .whitespacesAndNewlines) }
        return spaceSystemImageFallback
    }

    /// SF Symbol name safe for launcher icon rendering (never emoji).
    static func resolvedLauncherSystemImageName(_ stored: String) -> String {
        guard !presentsAsEmoji(stored) else { return launcherSystemImageFallback }
        if isValidSystemSymbolName(stored) { return stored.trimmingCharacters(in: .whitespacesAndNewlines) }
        return launcherSystemImageFallback
    }

    /// Canonical value to persist for a space icon slot.
    static func normalizedSpaceIconValue(_ stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return spaceSystemImageFallback }
        if presentsAsEmoji(trimmed) { return trimmed }
        if isValidSystemSymbolName(trimmed) { return trimmed }
        return spaceSystemImageFallback
    }

    /// Canonical value to persist for a launcher icon slot.
    static func normalizedLauncherIconValue(_ stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return launcherSystemImageFallback }
        if presentsAsEmoji(trimmed) { return trimmed }
        if isValidSystemSymbolName(trimmed) { return trimmed }
        return launcherSystemImageFallback
    }
}
