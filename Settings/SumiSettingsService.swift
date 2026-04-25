//
//  SumiSettingsService.swift
//  Sumi
//
//  Created by Maciek Bagiński on 03/08/2025.
//  Updated by Aether Aurelia on 15/11/2025.
//

import AppKit
import Security
import SwiftUI

@MainActor
@Observable
class SumiSettingsService {
    private let userDefaults: UserDefaults
    private let windowSchemeModeKey = "settings.windowSchemeMode"
    private let themeUseSystemColorsKey = "settings.themeUseSystemColors"
    private let themeStyledStatusPanelKey = "settings.themeStyledStatusPanel"
    private let themeBorderRadiusKey = "settings.themeBorderRadius"
    private let darkThemeStyleKey = "settings.darkThemeStyle"
    private let searchEngineKey = "settings.searchEngine"
    private let tabUnloadTimeoutKey = "settings.tabUnloadTimeout"
    private let askBeforeQuitKey = "settings.askBeforeQuit"
    private let sidebarPositionKey = "settings.sidebarPosition"
    private let sidebarCompactSpacesKey = "settings.sidebarCompactSpaces"
    private let topBarAddressViewKey = "settings.topBarAddressView"
    private let glanceEnabledKey = "settings.glanceEnabled"
    private let glanceActivationMethodKey = "settings.glanceActivationMethod"
    private let showSidebarToggleButtonKey = "settings.showSidebarToggleButton"
    private let showNewTabButtonInTabListKey = "settings.showNewTabButtonInTabList"
    private let tabListNewTabButtonPositionKey = "settings.tabListNewTabButtonPosition"
    private let showLinkStatusBarKey = "settings.showLinkStatusBar"
    private let showEssentialsUnloadIndicatorKey = "settings.showEssentialsUnloadIndicator"
    private let pinnedTabsLookKey = "settings.pinnedTabsLook"
    private let siteSearchEntriesKey = "settings.siteSearchEntries"
    private let didFinishOnboardingKey = "settings.didFinishOnboarding"
    private let tabLayoutKey = "settings.tabLayout"
    private let customSearchEnginesKey = "settings.customSearchEngines"
    private let memoryModeKey = "settings.memoryMode"

    var currentSettingsTab: SettingsTabs = .general

    /// Safari extensions vs SumiScripts, when `currentSettingsTab == .extensions`.
    var extensionsSettingsSubPane: SumiExtensionsSettingsSubPane = .safariExtensions

    var windowSchemeMode: WindowSchemeMode {
        didSet {
            userDefaults.set(windowSchemeMode.rawValue, forKey: windowSchemeModeKey)
        }
    }

    var themeUseSystemColors: Bool {
        didSet {
            userDefaults.set(themeUseSystemColors, forKey: themeUseSystemColorsKey)
        }
    }

    var themeStyledStatusPanel: Bool {
        didSet {
            userDefaults.set(themeStyledStatusPanel, forKey: themeStyledStatusPanelKey)
        }
    }

    var themeBorderRadius: Int {
        didSet {
            userDefaults.set(themeBorderRadius, forKey: themeBorderRadiusKey)
        }
    }

    var darkThemeStyle: DarkThemeStyle {
        didSet {
            userDefaults.set(darkThemeStyle.rawValue, forKey: darkThemeStyleKey)
        }
    }

    func resolvedCornerRadius(_ fallback: CGFloat) -> CGFloat {
        themeBorderRadius == -1 ? fallback : CGFloat(themeBorderRadius)
    }

    var searchEngineId: String {
        didSet {
            userDefaults.set(searchEngineId, forKey: searchEngineKey)
        }
    }

    var customSearchEngines: [CustomSearchEngine] {
        didSet {
            if let data = try? JSONEncoder().encode(customSearchEngines) {
                userDefaults.set(data, forKey: customSearchEnginesKey)
            }
        }
    }

    /// Resolves the current `searchEngineId` to a query template string.
    /// Checks built-in `SearchProvider` cases first, then custom engines.
    var resolvedSearchEngineTemplate: String {
        if let provider = SearchProvider(rawValue: searchEngineId) {
            return provider.queryTemplate
        }
        if let custom = customSearchEngines.first(where: { $0.id.uuidString == searchEngineId }) {
            return custom.urlTemplate
        }
        return SearchProvider.google.queryTemplate
    }
    
    var tabUnloadTimeout: TimeInterval {
        didSet {
            userDefaults.set(tabUnloadTimeout, forKey: tabUnloadTimeoutKey)
            // Notify compositor manager of timeout change
            NotificationCenter.default.post(name: .tabUnloadTimeoutChanged, object: nil, userInfo: ["timeout": tabUnloadTimeout])
        }
    }
    
    var askBeforeQuit: Bool {
        didSet {
            userDefaults.set(askBeforeQuit, forKey: askBeforeQuitKey)
        }
    }
    
    var sidebarPosition: SidebarPosition {
        didSet {
            if sidebarPosition != .left {
                sidebarPosition = .left
                return
            }
            userDefaults.set(sidebarPosition.rawValue, forKey: sidebarPositionKey)
        }
    }

    var sidebarCompactSpaces: Bool {
        didSet {
            userDefaults.set(sidebarCompactSpaces, forKey: sidebarCompactSpacesKey)
        }
    }
    
    var topBarAddressView: Bool {
        didSet {
            if topBarAddressView {
                topBarAddressView = false
                return
            }
            userDefaults.set(topBarAddressView, forKey: topBarAddressViewKey)
        }
    }

    var glanceEnabled: Bool {
        didSet {
            userDefaults.set(glanceEnabled, forKey: glanceEnabledKey)
        }
    }

    var glanceActivationMethod: GlanceActivationMethod {
        didSet {
            userDefaults.set(glanceActivationMethod.rawValue, forKey: glanceActivationMethodKey)
        }
    }

    var showSidebarToggleButton: Bool {
        didSet {
            userDefaults.set(showSidebarToggleButton, forKey: showSidebarToggleButtonKey)
        }
    }

    var showNewTabButtonInTabList: Bool {
        didSet {
            userDefaults.set(showNewTabButtonInTabList, forKey: showNewTabButtonInTabListKey)
        }
    }

    var tabListNewTabButtonPosition: TabListNewTabButtonPosition {
        didSet {
            userDefaults.set(tabListNewTabButtonPosition.rawValue, forKey: tabListNewTabButtonPositionKey)
        }
    }

    var showLinkStatusBar: Bool {
        didSet {
            userDefaults.set(showLinkStatusBar, forKey: showLinkStatusBarKey)
        }
    }

    var showEssentialsUnloadIndicator: Bool {
        didSet {
            userDefaults.set(showEssentialsUnloadIndicator, forKey: showEssentialsUnloadIndicatorKey)
        }
    }
    
    var pinnedTabsLook: PinnedTabsConfiguration {
        didSet {
            userDefaults.set(pinnedTabsLook, forKey: pinnedTabsLookKey)
        }
    }

    var siteSearchEntries: [SiteSearchEntry] {
        didSet {
            if let data = try? JSONEncoder().encode(siteSearchEntries) {
                userDefaults.set(data, forKey: siteSearchEntriesKey)
            }
        }
    }
    
    var tabLayout: TabLayout {
        didSet {
            userDefaults.set(tabLayout.rawValue, forKey: tabLayoutKey)
        }
    }

    var didFinishOnboarding: Bool {
        didSet {
            userDefaults.set(didFinishOnboarding, forKey: didFinishOnboardingKey)
        }
    }

    var memoryMode: SumiMemoryMode {
        didSet {
            userDefaults.set(memoryMode.rawValue, forKey: memoryModeKey)
        }
    }

    init(
        userDefaults: UserDefaults = .standard
    ) {
        self.userDefaults = userDefaults

        // Register default values
        userDefaults.register(defaults: [
            windowSchemeModeKey: WindowSchemeMode.auto.rawValue,
            themeUseSystemColorsKey: false,
            themeStyledStatusPanelKey: true,
            themeBorderRadiusKey: -1,
            darkThemeStyleKey: DarkThemeStyle.default.rawValue,
            searchEngineKey: SearchProvider.google.rawValue,
            // Default tab unload timeout: 60 minutes
            tabUnloadTimeoutKey: 3600.0,
            askBeforeQuitKey: true,
            sidebarPositionKey: SidebarPosition.left.rawValue,
            sidebarCompactSpacesKey: false,
            topBarAddressViewKey: false,
            glanceEnabledKey: true,
            glanceActivationMethodKey: GlanceActivationMethod.alt.rawValue,
            showSidebarToggleButtonKey: true,
            showNewTabButtonInTabListKey: true,
            tabListNewTabButtonPositionKey: TabListNewTabButtonPosition.bottom.rawValue,
            showLinkStatusBarKey: true,
            showEssentialsUnloadIndicatorKey: false,
            pinnedTabsLookKey: "large",
            didFinishOnboardingKey: true,
            tabLayoutKey: TabLayout.sidebar.rawValue,
            memoryModeKey: SumiMemoryMode.balanced.rawValue,
        ])

        // Initialize properties from UserDefaults
        // This will use the registered defaults if no value is set
        self.windowSchemeMode = WindowSchemeMode(
            rawValue: userDefaults.string(forKey: windowSchemeModeKey) ?? WindowSchemeMode.auto.rawValue
        ) ?? .auto
        self.themeUseSystemColors = userDefaults.bool(forKey: themeUseSystemColorsKey)
        self.themeStyledStatusPanel = userDefaults.bool(forKey: themeStyledStatusPanelKey)
        let storedBorderRadius = userDefaults.integer(forKey: themeBorderRadiusKey)
        self.themeBorderRadius = userDefaults.object(forKey: themeBorderRadiusKey) == nil ? -1 : storedBorderRadius
        self.darkThemeStyle = DarkThemeStyle(
            rawValue: userDefaults.string(forKey: darkThemeStyleKey) ?? DarkThemeStyle.default.rawValue
        ) ?? .default

        // searchEngineId: backward compatible — existing "google" string still works
        self.searchEngineId = userDefaults.string(forKey: searchEngineKey) ?? SearchProvider.google.rawValue

        if let ceData = userDefaults.data(forKey: customSearchEnginesKey),
           let decoded = try? JSONDecoder().decode([CustomSearchEngine].self, from: ceData) {
            self.customSearchEngines = decoded
        } else {
            self.customSearchEngines = []
        }
        
        // Initialize tab unload timeout
        self.tabUnloadTimeout = userDefaults.double(forKey: tabUnloadTimeoutKey)
        self.askBeforeQuit = userDefaults.bool(forKey: askBeforeQuitKey)
        self.sidebarPosition = SidebarPosition(rawValue: userDefaults.string(forKey: sidebarPositionKey) ?? "left") ?? SidebarPosition.left
        self.sidebarCompactSpaces = userDefaults.bool(forKey: sidebarCompactSpacesKey)
        self.topBarAddressView = userDefaults.bool(forKey: topBarAddressViewKey)
        if userDefaults.object(forKey: glanceEnabledKey) == nil {
            self.glanceEnabled = true
        } else {
            self.glanceEnabled = userDefaults.bool(forKey: glanceEnabledKey)
        }
        self.glanceActivationMethod = GlanceActivationMethod(
            rawValue: userDefaults.string(forKey: glanceActivationMethodKey) ?? GlanceActivationMethod.alt.rawValue
        ) ?? .alt
        if userDefaults.object(forKey: showSidebarToggleButtonKey) == nil {
            self.showSidebarToggleButton = true
        } else {
            self.showSidebarToggleButton = userDefaults.bool(forKey: showSidebarToggleButtonKey)
        }
        if userDefaults.object(forKey: showNewTabButtonInTabListKey) == nil {
            self.showNewTabButtonInTabList = true
        } else {
            self.showNewTabButtonInTabList = userDefaults.bool(forKey: showNewTabButtonInTabListKey)
        }
        self.tabListNewTabButtonPosition = TabListNewTabButtonPosition(
            rawValue: userDefaults.string(forKey: tabListNewTabButtonPositionKey) ?? TabListNewTabButtonPosition.bottom.rawValue
        ) ?? .bottom
        self.showLinkStatusBar = userDefaults.bool(forKey: showLinkStatusBarKey)
        self.showEssentialsUnloadIndicator = userDefaults.bool(forKey: showEssentialsUnloadIndicatorKey)
        self.pinnedTabsLook = PinnedTabsConfiguration(rawValue: userDefaults.string(forKey: pinnedTabsLookKey) ?? "large") ?? .large
        self.tabLayout = TabLayout(rawValue: userDefaults.string(forKey: tabLayoutKey) ?? TabLayout.sidebar.rawValue) ?? .sidebar
        self.didFinishOnboarding = userDefaults.bool(forKey: didFinishOnboardingKey)
        self.memoryMode = SumiMemoryMode(
            rawValue: userDefaults.string(forKey: memoryModeKey) ?? SumiMemoryMode.balanced.rawValue
        ) ?? .balanced

        if let data = userDefaults.data(forKey: siteSearchEntriesKey),
           let decoded = try? JSONDecoder().decode([SiteSearchEntry].self, from: data) {
            self.siteSearchEntries = decoded
        } else {
            self.siteSearchEntries = SiteSearchEntry.defaultSites
        }

        enforceSumiChromeDefaults()
    }

    /// Syncs sidebar tab + Extensions sub-pane from `sumi://settings?pane=…`.
    func applyNavigationFromSettingsSurfaceURL(_ url: URL) {
        guard SumiSurface.isSettingsSurfaceURL(url),
              let raw = SumiSurface.settingsPaneQuery(from: url)?.lowercased()
        else { return }
        switch raw {
        case "userscripts", "user_scripts":
            currentSettingsTab = .extensions
            extensionsSettingsSubPane = .userScripts
        case "extensions":
            currentSettingsTab = .extensions
            extensionsSettingsSubPane = .safariExtensions
        default:
            if let tab = SettingsTabs(paneQueryValue: raw) {
                currentSettingsTab = tab
            }
        }
    }

    /// URL for the active settings tab, including Userscripts as `pane=userScripts`.
    func settingsSurfaceURLForCurrentNavigation() -> URL {
        if currentSettingsTab == .extensions {
            switch extensionsSettingsSubPane {
            case .userScripts:
                return SumiSurface.settingsSurfaceURL(paneQuery: SettingsTabs.userScripts.paneQueryValue)
            case .safariExtensions:
                return SumiSurface.settingsSurfaceURL(paneQuery: SettingsTabs.extensions.paneQueryValue)
            }
        }
        return currentSettingsTab.settingsSurfaceURL
    }

    private func enforceSumiChromeDefaults() {
        if sidebarPosition != .left {
            sidebarPosition = .left
        }
        if topBarAddressView {
            topBarAddressView = false
        }
        if tabLayout != .sidebar {
            tabLayout = .sidebar
        }
        if !didFinishOnboarding {
            didFinishOnboarding = true
        }
    }
}

enum SumiMemoryMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case lightweight
    case balanced
    case performance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lightweight: return "Lightweight"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        }
    }
}

enum GlanceActivationMethod: String, CaseIterable, Identifiable {
    case ctrl = "ctrl"
    case alt = "alt"
    case shift = "shift"
    case meta = "meta"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ctrl: return "Ctrl + Click"
        case .alt: return "Option + Click"
        case .shift: return "Shift + Click"
        case .meta: return "Command + Click"
        }
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

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .night: return "Night"
        case .colorful: return "Colorful"
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let tabUnloadTimeoutChanged = Notification.Name("tabUnloadTimeoutChanged")
}

// MARK: - Environment Key
private struct SumiSettingsServiceKey: EnvironmentKey {
    @MainActor
    static var defaultValue: SumiSettingsService {
        // This should never be called since we always inject from SumiApp
        // But EnvironmentKey protocol requires a default value
        return SumiSettingsService()
    }
}

extension EnvironmentValues {
    var sumiSettings: SumiSettingsService {
        get { self[SumiSettingsServiceKey.self] }
        set { self[SumiSettingsServiceKey.self] = newValue }
    }
}
// MARK: - Tab Layout

enum TabLayout: String, CaseIterable, Identifiable {
    case sidebar
    case topOfWindow

    var id: String { rawValue }
}
