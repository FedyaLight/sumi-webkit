//
//  SumiPersistentGlyph.swift
//  Sumi
//
//  Validates persisted “glyph” strings used as either emoji text or SF Symbol
//  names so UI code never asks the system symbol set for invalid names.
//

import AppKit

enum SumiSpaceIconPresentation: Equatable {
    case defaultDot
    case emoji(String)
    case systemImage(String)
}

enum SumiPersistentGlyph {
    static let spaceDefaultIconValue = ""
    static let spaceDefaultDotDiameter: CGFloat = 6

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

    /// SF Symbol name safe for launcher icon rendering (never emoji).
    static func resolvedLauncherSystemImageName(_ stored: String) -> String {
        guard !presentsAsEmoji(stored) else { return launcherSystemImageFallback }
        if isValidSystemSymbolName(stored) { return stored.trimmingCharacters(in: .whitespacesAndNewlines) }
        return launcherSystemImageFallback
    }

    /// Canonical value to persist for a space icon slot.
    static func normalizedSpaceIconValue(_ stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return spaceDefaultIconValue
        }
        if presentsAsEmoji(trimmed) { return trimmed }
        if isValidSystemSymbolName(trimmed) { return trimmed }
        return spaceDefaultIconValue
    }

    static func resolvedSpaceIconPresentation(_ stored: String) -> SumiSpaceIconPresentation {
        let normalized = normalizedSpaceIconValue(stored)
        if normalized == spaceDefaultIconValue {
            return .defaultDot
        }
        if presentsAsEmoji(normalized) {
            return .emoji(normalized)
        }
        return .systemImage(normalized)
    }

    static func defaultSpaceDotImage(
        canvasSize: NSSize,
        dotDiameter: CGFloat = spaceDefaultDotDiameter
    ) -> NSImage {
        let image = NSImage(size: canvasSize)
        image.lockFocus()

        let rect = NSRect(
            x: (canvasSize.width - dotDiameter) / 2,
            y: (canvasSize.height - dotDiameter) / 2,
            width: dotDiameter,
            height: dotDiameter
        )
        NSColor.black.setFill()
        NSBezierPath(ovalIn: rect).fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
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
