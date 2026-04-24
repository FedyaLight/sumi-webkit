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
    case about

    private enum SidebarPlacement: Int {
        case primary
        case trailing
    }

    /// Sidebar order derived from enum declaration order, with explicit trailing tabs.
    static var ordered: [SettingsTabs] {
        let caseOrder = Dictionary(uniqueKeysWithValues: allCases.enumerated().map { ($1, $0) })
        return allCases
            .filter(\.showsInSettingsSidebar)
            .sorted { lhs, rhs in
                if lhs.sidebarPlacement != rhs.sidebarPlacement {
                    return lhs.sidebarPlacement.rawValue < rhs.sidebarPlacement.rawValue
                }
                return (caseOrder[lhs] ?? 0) < (caseOrder[rhs] ?? 0)
            }
    }

    private var showsInSettingsSidebar: Bool {
        switch self {
        case .userScripts:
            return false
        default:
            return true
        }
    }

    private var sidebarPlacement: SidebarPlacement {
        switch self {
        case .about:
            return .trailing
        default:
            return .primary
        }
    }

    var name: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Theme"
        case .privacy: return "Privacy"
        case .profiles: return "Spaces & Essentials"
        case .shortcuts: return "Keyboard"
        case .userScripts: return "Userscripts"
        case .extensions: return "Extensions"
        case .advanced: return "Data & Recovery"
        case .about: return "About Sumi"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .privacy: return "lock.shield"
        case .profiles: return "square.grid.2x2"
        case .shortcuts: return "keyboard"
        case .userScripts: return "curlybraces.square"
        case .extensions: return "puzzlepiece.extension"
        case .advanced: return "internaldrive"
        case .about: return "info.circle"
        }
    }

    /// Query value persisted in `sumi://settings?pane=…`.
    var paneQueryValue: String {
        switch self {
        case .appearance: return "appearance"
        case .general: return "general"
        case .privacy: return "privacy"
        case .profiles: return "profiles"
        case .shortcuts: return "shortcuts"
        case .userScripts: return "userScripts"
        case .extensions: return "extensions"
        case .advanced: return "advanced"
        case .about: return "about"
        }
    }

    init?(paneQueryValue: String) {
        switch paneQueryValue.lowercased() {
        case "appearance": self = .appearance
        case "general": self = .general
        case "privacy": self = .privacy
        case "profiles": self = .profiles
        case "shortcuts": self = .shortcuts
        case "userscripts", "user_scripts": self = .userScripts
        case "extensions": self = .extensions
        case "advanced": self = .advanced
        case "about": self = .about
        default: return nil
        }
    }

    var settingsSurfaceURL: URL {
        SumiSurface.settingsSurfaceURL(paneQuery: paneQueryValue)
    }
}
