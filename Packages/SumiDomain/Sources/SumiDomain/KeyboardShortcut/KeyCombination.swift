import Foundation

public struct KeyCombination: Hashable, Codable, Sendable {
    public let key: String
    public let modifiers: Modifiers

    public init(key: String, modifiers: Modifiers = []) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    public var lookupKey: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.shift) { parts.append("shift") }
        parts.append(key.lowercased())
        return parts.joined(separator: "+")
    }
}

public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int

    public static let command = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
