//
//  SumiProfileIcon.swift
//  Sumi
//
//  Profile icons are stored and rendered as emoji. They do not share the
//  generic SF Symbol validation path used by spaces and launchers.
//

import Foundation

enum SumiProfileIcon {
    static let defaultIcon = SumiPersistentGlyph.spaceDefaultIconValue
    static let defaultDotDiameter = SumiPersistentGlyph.spaceDefaultDotDiameter

    static func storedValue(_ icon: String) -> String {
        icon.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func usesDefaultIcon(_ icon: String) -> Bool {
        storedValue(icon).isEmpty
    }
}
