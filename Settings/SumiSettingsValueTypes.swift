//
//  SumiSettingsValueTypes.swift
//  Sumi
//
//  Persisted settings value types: startup, new tab, memory, and chrome
//  presentation modes with their validation helpers.
//

import Foundation
import SumiDomain

enum FloatingBarEmptyStateMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case compact
    case topLinks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .topLinks: return "Top Links"
        }
    }
}

enum SumiStartupMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case nothing
    case restorePreviousSession
    case specificPage

    var id: String { rawValue }

    static func persistedValue(_ rawValue: String?) -> SumiStartupMode {
        switch rawValue {
        case Self.nothing.rawValue:
            return .nothing
        case Self.restorePreviousSession.rawValue:
            return .restorePreviousSession
        case Self.specificPage.rawValue:
            return .specificPage
        default:
            return .restorePreviousSession
        }
    }

    var title: String {
        switch self {
        case .nothing:
            return "Nothing"
        case .restorePreviousSession:
            return "Restore previous session"
        case .specificPage:
            return "Open a specific page"
        }
    }

    var subtitle: String {
        switch self {
        case .nothing:
            return "Start with a clean empty window. Your previous session stays available from History."
        case .restorePreviousSession:
            return "Restore regular tabs, windows, and active pinned launcher instances."
        case .specificPage:
            return "Open one configured page in a regular tab."
        }
    }
}

enum SumiStartupPageURL {
    static let defaultURLString = SumiSurface.emptyTabURL.absoluteString
    static let allowedSchemes: Set<String> = ["http", "https", "file", "about", "sumi"]

    static func normalizedURLString(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased() {
            guard allowedSchemes.contains(scheme) else { return nil }
            if ["http", "https"].contains(scheme) {
                guard hasHTTPHost(url) else {
                    return nil
                }
            }
            return trimmed
        }

        guard isBareDomain(trimmed) else { return nil }
        let normalized = "https://\(trimmed)"
        guard let url = URL(string: normalized),
              hasHTTPHost(url)
        else {
            return nil
        }
        return normalized
    }

    static func validatedURL(from input: String) -> URL? {
        normalizedURLString(from: input).flatMap(URL.init(string:))
    }

    static func runtimeURL(from input: String) -> URL {
        validatedURL(from: input) ?? SumiSurface.emptyTabURL
    }

    static func validationMessage(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Sumi will open a blank page until you enter a URL."
        }
        return normalizedURLString(from: trimmed) == nil
            ? "Enter a URL such as https://example.com or example.com."
            : nil
    }

    private static func isBareDomain(_ value: String) -> Bool {
        guard !value.contains(where: \.isWhitespace),
              value.contains("."),
              !value.hasPrefix("."),
              !value.hasSuffix(".")
        else {
            return false
        }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else {
            return false
        }
        return labels.last?.contains(where: { $0.isLetter || $0.isNumber }) == true
    }

    private static func hasHTTPHost(_ url: URL) -> Bool {
        url.host(percentEncoded: false)?.isEmpty == false || url.host?.isEmpty == false
    }
}

enum SumiMemoryMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case moderate
    case balanced
    case maximum
    case custom

    var id: String { rawValue }

    static func persistedValue(_ rawValue: String?) -> SumiMemoryMode {
        switch rawValue {
        case Self.moderate.rawValue:
            return .moderate
        case Self.balanced.rawValue:
            return .balanced
        case Self.maximum.rawValue:
            return .maximum
        case Self.custom.rawValue:
            return .custom
        case "lightweight":
            return .maximum
        case "performance":
            return .moderate
        default:
            return .balanced
        }
    }

    var displayName: String {
        switch self {
        case .moderate: return "Moderate"
        case .balanced: return "Balanced"
        case .maximum: return "Maximum"
        case .custom: return "Custom Deactivation Delay"
        }
    }
}

enum SumiMemorySaverCustomDelay {
    static let minimum: TimeInterval = 60
    static let maximum: TimeInterval = 2 * 60 * 60
    static let defaultDelay: TimeInterval = 2 * 60 * 60
    static let presetOptions: [TimeInterval] = [
        2 * 60 * 60,
        60 * 60,
        30 * 60,
        15 * 60,
        5 * 60,
        60,
    ]

    static func clamped(_ delay: TimeInterval) -> TimeInterval {
        guard delay.isFinite, delay > 0 else { return defaultDelay }
        return min(max(delay, minimum), maximum)
    }

    static func validatedOrDefault(_ delay: TimeInterval?) -> TimeInterval {
        guard let delay, delay.isFinite, delay > 0 else { return defaultDelay }
        return nearestPreset(to: delay)
    }

    static func nearestPreset(to delay: TimeInterval) -> TimeInterval {
        let clampedDelay = clamped(delay)
        return presetOptions.min { lhs, rhs in
            let lhsDistance = abs(lhs - clampedDelay)
            let rhsDistance = abs(rhs - clampedDelay)
            if lhsDistance == rhsDistance {
                return lhs > rhs
            }
            return lhsDistance < rhsDistance
        } ?? defaultDelay
    }
}

enum TabListNewTabButtonPosition: String, CaseIterable, Identifiable {
    case top = "top"
    case bottom = "bottom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
}

enum WindowSchemeMode: String, CaseIterable, Identifiable {
    case auto = "auto"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum DarkThemeStyle: String, CaseIterable, Identifiable {
    case `default` = "default"
    case night = "night"
    case colorful = "colorful"

    var id: String { rawValue }
}

enum SumiNewTabMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case floatingBar
    case specificPage

    var id: String { rawValue }

    static func persistedValue(_ rawValue: String?) -> SumiNewTabMode {
        switch rawValue {
        case Self.floatingBar.rawValue:
            return .floatingBar
        case Self.specificPage.rawValue:
            return .specificPage
        default:
            return .floatingBar
        }
    }

    var title: String {
        switch self {
        case .floatingBar:
            return "Floating Bar"
        case .specificPage:
            return "Specific Page"
        }
    }
}

enum SumiNewTabPageURL {
    static let defaultURLString = SumiSurface.emptyTabURL.absoluteString
    static let allowedSchemes: Set<String> = ["http", "https", "file", "about", "sumi"]

    static func normalizedURLString(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased() {
            guard allowedSchemes.contains(scheme) else { return nil }
            if ["http", "https"].contains(scheme) {
                guard hasHTTPHost(url) else {
                    return nil
                }
            }
            return trimmed
        }

        guard isBareDomain(trimmed) else { return nil }
        let normalized = "https://\(trimmed)"
        guard let url = URL(string: normalized),
              hasHTTPHost(url)
        else {
            return nil
        }
        return normalized
    }

    static func validatedURL(from input: String) -> URL? {
        normalizedURLString(from: input).flatMap(URL.init(string:))
    }

    static func runtimeURL(from input: String) -> URL {
        validatedURL(from: input) ?? SumiSurface.emptyTabURL
    }

    static func validationMessage(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Sumi will open a blank page until you enter a URL."
        }
        return normalizedURLString(from: trimmed) == nil
            ? "Enter a URL such as https://example.com or example.com."
            : nil
    }

    private static func isBareDomain(_ value: String) -> Bool {
        guard !value.contains(where: \.isWhitespace),
              value.contains("."),
              !value.hasPrefix("."),
              !value.hasSuffix(".")
        else {
            return false
        }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else {
            return false
        }
        return labels.last?.contains(where: { $0.isLetter || $0.isNumber }) == true
    }

    private static func hasHTTPHost(_ url: URL) -> Bool {
        url.host(percentEncoded: false)?.isEmpty == false || url.host?.isEmpty == false
    }
}
