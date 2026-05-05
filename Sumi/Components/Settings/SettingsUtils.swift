//
//  SettingsUtils.swift
//  Sumi
//
//  Created by Maciek Bagiński on 03/08/2025.
//
import Foundation

enum SettingsPaneGroup: String, CaseIterable, Hashable {
    case browser = "Browser"
    case browsing = "Browsing"
    case privacy = "Privacy"
    case system = "System"
    case support = "Support"
}

struct SettingsPaneDescriptor: Identifiable, Hashable {
    let tab: SettingsTabs
    let title: String
    let subtitle: String
    let icon: String
    let group: SettingsPaneGroup
    let keywords: [String]

    var id: SettingsTabs { tab }

    static let all: [SettingsPaneDescriptor] = SettingsTabs.ordered.map(Self.descriptor)

    static func descriptor(for tab: SettingsTabs) -> SettingsPaneDescriptor {
        switch tab {
        case .general:
            return SettingsPaneDescriptor(
                tab: tab,
                title: "General",
                subtitle: "Window behavior, Glance, search engines, and site search.",
                icon: tab.icon,
                group: .browser,
                keywords: [
                    "quit", "url", "glance", "search", "engine",
                    "site search", "command palette"
                ]
            )
        case .startup:
            return SettingsPaneDescriptor(
                tab: tab,
                title: "Startup",
                subtitle: "Choose what Sumi opens when a new app session starts.",
                icon: tab.icon,
                group: .browser,
                keywords: [
                    "startup", "launch", "restore", "previous session",
                    "pinned", "essential", "launcher", "homepage", "start page"
                ]
            )
        case .appearance:
            return SettingsPaneDescriptor(
                tab: tab,
                title: "Appearance",
                subtitle: "Sidebar chrome and tab-list controls.",
                icon: tab.icon,
                group: .browser,
                keywords: [
                    "sidebar", "side", "compact spaces", "new tab",
                    "toggle button", "tab list", "button position",
                    "hover", "preview link", "status area"
                ]
            )
        case .performance:
            return SettingsPaneDescriptor(
                tab: tab,
                title: "Performance",
                subtitle: "Memory Saver and inactive tab deactivation behavior.",
                icon: tab.icon,
                group: .browsing,
                keywords: [
                    "memory", "saver", "inactive", "deactivate", "tabs",
                    "reload", "custom delay", "essentials"
                ]
            )
        case .privacy:
            return SettingsPaneDescriptor(
                tab: tab,
                title: "Privacy & Security",
                subtitle: "Tracking protection, ad blocking, permissions, and site settings.",
                icon: tab.icon,
                group: .privacy,
                keywords: [
                    "tracking", "protection", "ad blocking", "tracker data",
                    "site overrides", "rules", "privacy", "security",
                    "site settings", "permissions", "camera", "microphone",
                    "location", "notifications", "popups", "pop-ups",
                    "autoplay", "storage access", "screen sharing"
                ]
            )
        case .profiles:
            return SettingsPaneDescriptor(
                tab: tab,
                title: "Profiles & Spaces",
                subtitle: "Profiles, personas, and space assignments.",
                icon: tab.icon,
                group: .browsing,
                keywords: [
                    "profiles", "spaces", "personas", "assignments"
                ]
            )
        case .shortcuts:
            return SettingsPaneDescriptor(
                tab: tab,
                title: "Keyboard",
                subtitle: "Search, customize, enable, and reset keyboard shortcuts.",
                icon: tab.icon,
                group: .system,
                keywords: [
                    "keyboard", "shortcuts", "hotkeys", "commands", "reset",
                    "customize", "navigation"
                ]
            )
        case .userScripts:
            return SettingsPaneDescriptor(
                tab: tab,
                title: "Userscripts",
                subtitle: "Manage Sumi userscripts from the Extensions settings pane.",
                icon: tab.icon,
                group: .system,
                keywords: ["userscripts", "scripts", "greasemonkey", "tampermonkey"]
            )
        case .extensions:
            return SettingsPaneDescriptor(
                tab: tab,
                title: "Extensions",
                subtitle: "Safari extensions and userscripts for Sumi.",
                icon: tab.icon,
                group: .system,
                keywords: [
                    "extensions", "safari", "webextension", "appex",
                    "manifest", "userscripts", "install", "uninstall"
                ]
            )
        case .advanced:
            return SettingsPaneDescriptor(
                tab: tab,
                title: "Data & Recovery",
                subtitle: "Local runtime data folders, snapshots, and recovery tools.",
                icon: tab.icon,
                group: .support,
                keywords: [
                    "data", "recovery", "backup", "export", "folder",
                    "application support", "swiftdata"
                ]
            )
        case .about:
            return SettingsPaneDescriptor(
                tab: tab,
                title: "About Sumi",
                subtitle: "Version and build information.",
                icon: tab.icon,
                group: .support,
                keywords: ["about", "version", "build", "sumi"]
            )
        }
    }

    static func filtered(by query: String) -> [SettingsPaneDescriptor] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.matches(trimmed) }
    }

    func matches(_ query: String) -> Bool {
        let terms = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return true }

        let searchableText = ([title, subtitle, group.rawValue] + keywords)
            .joined(separator: " ")
            .lowercased()
        return terms.allSatisfy { searchableText.contains($0) }
    }
}

struct SumiSettingsSiteSettingsFilter: Equatable, Hashable {
    let requestingOriginIdentity: String?
    let topOriginIdentity: String?
    let displayDomain: String?

    init(
        requestingOriginIdentity: String?,
        topOriginIdentity: String?,
        displayDomain: String?
    ) {
        self.requestingOriginIdentity = requestingOriginIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.topOriginIdentity = topOriginIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayDomain = displayDomain?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        displayDomain: String?
    ) {
        self.init(
            requestingOriginIdentity: requestingOrigin.identity,
            topOriginIdentity: topOrigin.identity,
            displayDomain: displayDomain
        )
    }
}

enum SumiPrivacySettingsRoute: Equatable, Hashable {
    case overview
    case siteSettings(SumiSettingsSiteSettingsFilter?)

    var isSiteSettings: Bool {
        if case .siteSettings = self { return true }
        return false
    }

    var siteSettingsFilter: SumiSettingsSiteSettingsFilter? {
        if case .siteSettings(let filter) = self { return filter }
        return nil
    }
}

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
    case startup
    case appearance
    case performance
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

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .startup: return "power"
        case .appearance: return "paintpalette"
        case .performance: return "speedometer"
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
        case .startup: return "startup"
        case .performance: return "performance"
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
        case "startup": self = .startup
        case "performance": self = .performance
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
