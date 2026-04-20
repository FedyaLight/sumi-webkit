//
//  SumiPersistentGlyph.swift
//  Sumi
//
//  Validates persisted “glyph” strings used as either emoji text or SF Symbol
//  names so SwiftUI never asks the system symbol set for invalid names.
//

import AppKit
import SwiftUI

enum SumiPersistentGlyph {
    /// Default SF Symbol for spaces (matches `Space`’s initializer default).
    static let spaceSystemImageFallback = "square.grid.2x2"
    /// Default SF Symbol for profiles (matches `Profile`’s initializer default).
    static let profileSystemImageFallback = "person.crop.circle"
    /// Default launcher fallback when no bitmap favicon or custom launcher icon exists.
    static let launcherSystemImageFallback = "globe"

    /// True when the string should be drawn with `Text` (emoji / pictographic slot).
    static func presentsAsEmoji(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
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

    /// SF Symbol name safe for `Image(systemName:)` / `Label(..., systemImage:)` (never emoji).
    static func resolvedProfileSystemImageName(_ stored: String) -> String {
        guard !presentsAsEmoji(stored) else { return profileSystemImageFallback }
        if isValidSystemSymbolName(stored) { return stored.trimmingCharacters(in: .whitespacesAndNewlines) }
        return profileSystemImageFallback
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

    /// Canonical value to persist for a profile icon slot.
    static func normalizedProfileIconValue(_ stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return profileSystemImageFallback }
        if presentsAsEmoji(trimmed) { return trimmed }
        if isValidSystemSymbolName(trimmed) { return trimmed }
        return profileSystemImageFallback
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

// MARK: - SwiftUI

/// Renders a space icon from persisted storage (emoji `Text` or validated SF Symbol).
struct SumiSpaceGlyphDisplay: View {
    let icon: String
    var font: Font = .body

    var body: some View {
        Group {
            if SumiPersistentGlyph.presentsAsEmoji(icon) {
                Text(icon).font(font)
            } else {
                Image(systemName: SumiPersistentGlyph.resolvedSpaceSystemImageName(icon))
                    .font(font)
            }
        }
    }
}

/// Renders a profile icon from persisted storage (emoji `Text` or validated SF Symbol).
struct SumiProfileGlyphDisplay: View {
    let icon: String
    var font: Font = .body

    var body: some View {
        Group {
            if SumiPersistentGlyph.presentsAsEmoji(icon) {
                Text(icon).font(font)
            } else {
                Image(systemName: SumiPersistentGlyph.resolvedProfileSystemImageName(icon))
                    .font(font)
            }
        }
    }
}

/// Renders a launcher icon override from persisted storage (emoji `Text` or validated SF Symbol).
struct SumiLauncherGlyphDisplay: View {
    let icon: String
    var font: Font = .body

    var body: some View {
        Group {
            if SumiPersistentGlyph.presentsAsEmoji(icon) {
                Text(icon).font(font)
            } else {
                Image(systemName: SumiPersistentGlyph.resolvedLauncherSystemImageName(icon))
                    .font(font)
            }
        }
    }
}

/// `Label` for menus/pickers where `systemImage:` must not receive emoji or invalid names.
struct SumiProfileMenuLabel: View {
    let name: String
    let icon: String

    var body: some View {
        if SumiPersistentGlyph.presentsAsEmoji(icon) {
            Label {
                Text(name)
            } icon: {
                Text(icon)
            }
        } else {
            Label(name, systemImage: SumiPersistentGlyph.resolvedProfileSystemImageName(icon))
        }
    }
}

/// `Label` for menus where the space icon may be emoji or an SF Symbol name.
struct SumiSpaceMenuLabel: View {
    let name: String
    let icon: String

    var body: some View {
        if SumiPersistentGlyph.presentsAsEmoji(icon) {
            Label {
                Text(name)
            } icon: {
                Text(icon)
            }
        } else {
            Label(name, systemImage: SumiPersistentGlyph.resolvedSpaceSystemImageName(icon))
        }
    }
}
