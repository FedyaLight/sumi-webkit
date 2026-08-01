//
//  SettingsUtils.swift
//  Sumi
//
//
import Foundation
import SumiDomain
import SwiftUI

enum SettingsPaneGroup: String, CaseIterable, Hashable {
    case browser = "Browser"
    case browsing = "Browsing"
    case privacy = "Privacy"
    case system = "System"
    case support = "Support"

    var localizedTitle: String {
        switch self {
        case .browser:
            String(localized: "Browser")
        case .browsing:
            String(localized: "Browsing")
        case .privacy:
            String(localized: "Privacy")
        case .system:
            String(localized: "System")
        case .support:
            String(localized: "Support")
        }
    }
}

struct SettingsPaneDescriptor: Identifiable, Hashable {
    let tab: SettingsTabs
    let title: String
    let subtitle: String
    let icon: String
    let group: SettingsPaneGroup
    let keywords: [String]

    var id: SettingsTabs { tab }

    var iconColor: Color {
        tab.iconColor
    }

    static let all: [SettingsPaneDescriptor] = SettingsTabs.ordered.map(Self.descriptor)

    static func descriptor(for tab: SettingsTabs) -> SettingsPaneDescriptor {
        switch tab {
        case .general:
            return SettingsPaneDescriptor(
                tab: tab,
                title: String(localized: "General"),
                subtitle: String(localized: "Window behavior, Glance, search engines, and site search."),
                icon: tab.icon,
                group: .browser,
                keywords: [
                    "quit", "url", "glance", "search", "engine",
                    "site search", "command palette",
                ]
            )
        case .startup:
            return SettingsPaneDescriptor(
                tab: tab,
                title: String(localized: "Startup"),
                subtitle: String(localized: "Choose what Sumi opens when a new app session starts."),
                icon: tab.icon,
                group: .browser,
                keywords: [
                    "startup", "launch", "restore", "previous session",
                    "pinned", "essential", "launcher", "homepage", "start page",
                ]
            )
        case .downloads:
            return SettingsPaneDescriptor(
                tab: tab,
                title: String(localized: "Downloads"),
                subtitle: String(localized: "Download destination and file handling behavior."),
                icon: tab.icon,
                group: .browser,
                keywords: [
                    "downloads", "folder", "save files", "applications",
                    "handlers", "open file", "mime", "content type",
                ]
            )
        case .appearance:
            return SettingsPaneDescriptor(
                tab: tab,
                title: String(localized: "Appearance"),
                subtitle: String(localized: "Sidebar chrome and tab-list controls."),
                icon: tab.icon,
                group: .browser,
                keywords: [
                    "sidebar", "side", "new tab",
                    "toggle button", "tab list", "button position",
                    "hover", "preview link", "status area",
                ]
            )
        case .performance:
            return SettingsPaneDescriptor(
                tab: tab,
                title: String(localized: "Performance"),
                subtitle: String(localized: "Memory Saver, Energy Saver, and inactive tab deactivation behavior."),
                icon: tab.icon,
                group: .browsing,
                keywords: [
                    "memory", "saver", "inactive", "deactivate", "tabs",
                    "reload", "custom delay", "essentials", "energy", "battery",
                    "low power", "thermal", "animations", "transparency", "gradient",
                ]
            )
        case .privacy:
            return SettingsPaneDescriptor(
                tab: tab,
                title: String(localized: "Privacy & Security"),
                subtitle: String(localized: "Tracking protection, ad blocking, permissions, and site settings."),
                icon: tab.icon,
                group: .privacy,
                keywords: [
                    "tracking", "protection", "ad blocking", "protection bundles",
                    "tracker",
                    "site overrides", "rules", "privacy", "security",
                    "site settings", "permissions", "camera", "microphone",
                    "location", "notifications", "popups", "pop-ups",
                    "autoplay", "storage access", "screen sharing",
                ]
            )
        case .profiles:
            return SettingsPaneDescriptor(
                tab: tab,
                title: String(localized: "Profiles"),
                subtitle: String(localized: "Isolated browsing data and profile management."),
                icon: tab.icon,
                group: .browsing,
                keywords: [
                    "profiles", "spaces", "website data", "cookies",
                    "cache", "local storage", "history",
                ]
            )
        case .shortcuts:
            return SettingsPaneDescriptor(
                tab: tab,
                title: String(localized: "Keyboard"),
                subtitle: String(localized: "Search, customize, enable, and reset keyboard shortcuts."),
                icon: tab.icon,
                group: .system,
                keywords: [
                    "keyboard", "shortcuts", "hotkeys", "commands", "reset",
                    "customize", "navigation",
                ]
            )
        case .extensions:
            return SettingsPaneDescriptor(
                tab: tab,
                title: String(localized: "Extensions"),
                subtitle: String(localized: "Extension runtime status and installed extensions."),
                icon: tab.icon,
                group: .system,
                keywords: [
                    "extensions", "webextension", "manifest", "safari",
                    "uninstall",
                ]
            )
        case .advanced:
            return SettingsPaneDescriptor(
                tab: tab,
                title: String(localized: "Data & Recovery"),
                subtitle: String(localized: "Local runtime data folders, snapshots, and recovery tools."),
                icon: tab.icon,
                group: .support,
                keywords: [
                    "data", "recovery", "backup", "export", "folder",
                    "application support", "swiftdata",
                ]
            )
        case .about:
            return SettingsPaneDescriptor(
                tab: tab,
                title: String(localized: "About Sumi"),
                subtitle: String(localized: "Version and build information."),
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

        let searchableText = ([title, subtitle, group.rawValue, group.localizedTitle] + keywords)
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

enum SettingsTabs: Hashable, CaseIterable {
    case general
    case appearance
    case downloads
    case startup
    case performance
    case privacy
    case profiles
    case shortcuts
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
            .sorted { lhs, rhs in
                if lhs.sidebarPlacement != rhs.sidebarPlacement {
                    return lhs.sidebarPlacement.rawValue < rhs.sidebarPlacement.rawValue
                }
                return (caseOrder[lhs] ?? 0) < (caseOrder[rhs] ?? 0)
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
        case .downloads: return "arrow.down.circle"
        case .appearance: return "paintpalette"
        case .performance: return "speedometer"
        case .privacy: return "lock.shield"
        case .profiles: return "person.2"
        case .shortcuts: return "keyboard"
        case .extensions: return "puzzlepiece.extension"
        case .advanced: return "internaldrive"
        case .about: return "info.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: return .gray
        case .startup: return .green
        case .downloads: return .blue
        case .appearance: return .purple
        case .performance: return .orange
        case .privacy: return .blue
        case .profiles: return .cyan
        case .shortcuts: return .indigo
        case .extensions: return .teal
        case .advanced: return .brown
        case .about: return .gray
        }
    }

}
