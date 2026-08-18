//
//  SumiSettingsValueTypes.swift
//  Sumi
//
//  Persisted settings value types: startup, new tab, memory, and chrome
//  presentation modes with their validation helpers.
//

import Foundation
import SumiDomain

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

enum SumiMemoryMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case off
    case moderate
    case balanced
    case maximum
    case custom

    var id: String { rawValue }

    static func persistedValue(_ rawValue: String?) -> SumiMemoryMode {
        switch rawValue {
        case Self.off.rawValue:
            return .off
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
        case .off: return "Off"
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
    case commandPalette
    case specificPage

    var id: String { rawValue }

    static func persistedValue(_ rawValue: String?) -> SumiNewTabMode {
        switch rawValue {
        case Self.commandPalette.rawValue:
            return .commandPalette
        case Self.specificPage.rawValue:
            return .specificPage
        default:
            return .commandPalette
        }
    }

    var title: String {
        switch self {
        case .commandPalette:
            return "Command Palette"
        case .specificPage:
            return "Specific Page"
        }
    }
}
