//
//  SettingsUtils.swift
//  Sumi
//
//  Created by Maciek Bagiński on 03/08/2025.
//
import Foundation

/// Which detail is shown inside Settings → Extensions (segmented control).
enum SumiExtensionsSettingsSubPane: String, CaseIterable, Hashable {
    case safariExtensions
    case userScripts

    var segmentTitle: String {
        switch self {
        case .safariExtensions: return "Extensions"
        case .userScripts: return "Userscripts"
        }
    }
}

enum SettingsTabs: Hashable, CaseIterable {
    case general
    case appearance
    case privacy
    case profiles
    case shortcuts
    case userScripts
    case extensions
    case advanced
    
    /// Sidebar order. Userscripts lives under the Extensions pane (segmented control).
    static var ordered: [SettingsTabs] {
        [.appearance, .general, .privacy, .profiles, .shortcuts, .extensions, .advanced]
    }
    
    var name: String {
        switch self {
        case .general: return "Layout"
        case .appearance: return "Theme"
        case .privacy: return "Privacy"
        case .profiles: return "Spaces & Essentials"
        case .shortcuts: return "Keyboard"
        case .userScripts: return "Userscripts"
        case .extensions: return "Extensions"
        case .advanced: return "Data & Recovery"
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "rectangle.3.offgrid"
        case .appearance: return "paintpalette"
        case .privacy: return "lock.shield"
        case .profiles: return "square.grid.2x2"
        case .shortcuts: return "keyboard"
        case .userScripts: return "curlybraces.square"
        case .extensions: return "puzzlepiece.extension"
        case .advanced: return "internaldrive"
        }
    }

    /// Query value persisted in `sumi://settings?pane=…`.
    var paneQueryValue: String {
        switch self {
        case .general: return "general"
        case .appearance: return "appearance"
        case .privacy: return "privacy"
        case .profiles: return "profiles"
        case .shortcuts: return "shortcuts"
        case .userScripts: return "userScripts"
        case .extensions: return "extensions"
        case .advanced: return "advanced"
        }
    }

    init?(paneQueryValue: String) {
        switch paneQueryValue.lowercased() {
        case "general": self = .general
        case "appearance": self = .appearance
        case "privacy": self = .privacy
        case "profiles": self = .profiles
        case "shortcuts": self = .shortcuts
        case "userscripts", "user_scripts": self = .userScripts
        case "extensions": self = .extensions
        case "advanced": self = .advanced
        default: return nil
        }
    }

    var settingsSurfaceURL: URL {
        SumiSurface.settingsSurfaceURL(paneQuery: paneQueryValue)
    }
}
