//
//  SumiProfileIcon.swift
//  SumiDomain
//
//  Profile icons are stored and rendered as emoji. They do not share the
//  generic SF Symbol validation path used by spaces and launchers.
//

import Foundation

public enum SumiProfileIcon {
    /// Empty string means “use the default profile dot” in UI.
    public static let defaultIcon = ""
    public static let defaultDotDiameter: CGFloat = 6

    public static func storedValue(_ icon: String) -> String {
        icon.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func usesDefaultIcon(_ icon: String) -> Bool {
        storedValue(icon).isEmpty
    }
}
