//
//  SpaceHoverLabel.swift
//  Sumi
//
//  What the spaces-strip hover label shows: the space's name plus one glyph per
//  key of the shortcut that activates it.
//

import Foundation
import SumiDomain

struct SpaceHoverLabel: Equatable, Identifiable {
    let spaceID: UUID
    let title: String
    /// One entry per key the user presses (`["⌃", "1"]`). Empty when the space
    /// has no shortcut — either it sits past the covered range or the user
    /// cleared the binding.
    let shortcutGlyphs: [String]

    var id: UUID { spaceID }
}

/// Resolves a strip position into a renderable label.
///
/// Callers hand over a space and where it sits in the strip; everything else —
/// which action covers that position, whether it is still bound, and how a key
/// combination decomposes into glyphs — stays behind this call.
enum SpaceHoverLabelBuilder {
    @MainActor
    static func label(
        for space: Space,
        at index: Int,
        shortcuts: KeyboardShortcutManager
    ) -> SpaceHoverLabel {
        SpaceHoverLabel(
            spaceID: space.id,
            title: space.name,
            shortcutGlyphs: glyphs(forSpaceAt: index, shortcuts: shortcuts)
        )
    }

    @MainActor
    private static func glyphs(
        forSpaceAt index: Int,
        shortcuts: KeyboardShortcutManager
    ) -> [String] {
        guard let action = SpaceSwitchShortcuts.action(forSpaceAt: index),
              let keyCombination = shortcuts.shortcut(for: action)?.keyCombination
        else { return [] }
        return KeyboardShortcutPresentation.glyphs(for: keyCombination)
    }
}
