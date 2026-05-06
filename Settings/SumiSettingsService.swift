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
    private let themeBorderRadiusKey = "settings.themeBorderRadius"
    private let darkThemeStyleKey = "settings.darkThemeStyle"
    private let searchEngineKey = "settings.searchEngine"
    private let tabUnloadTimeoutKey = "settings.tabUnloadTimeout"
    private let askBeforeQuitKey = "settings.askBeforeQuit"
    private let sidebarPositionKey = "settings.sidebarPosition"
    private let sidebarCompactSpacesKey = "settings.sidebarCompactSpaces"
    private let topBarAddressViewKey = "settings.topBarAddressView"
    private let glanceEnabledKey = "settings.glanceEnabled"
    private let showSidebarToggleButtonKey = "settings.showSidebarToggleButton"
    private let showNewTabButtonInTabListKey = "settings.showNewTabButtonInTabList"
    private let tabListNewTabButtonPositionKey = "settings.tabListNewTabButtonPosition"
    private let showLinkStatusBarKey = "settings.showLinkStatusBar"
    private let siteSearchEntriesKey = "settings.siteSearchEntries"
    private let didFinishOnboardingKey = "settings.didFinishOnboarding"
    private let tabLayoutKey = "settings.tabLayout"
    private let customSearchEnginesKey = "settings.customSearchEngines"
    private let memoryModeKey = "settings.memoryMode"
    private let memorySaverCustomDeactivationDelayKey = "settings.memorySaver.customDeactivationDelay"
    private let startupModeKey = "settings.startup.mode"
    private let startupPageURLStringKey = "settings.startup.pageURL"

    var currentSettingsTab: SettingsTabs = .general

    var privacySettingsRoute: SumiPrivacySettingsRoute = .overview

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
            NotificationCenter.default.post(name: .sumiMemorySaverPolicyChanged, object: nil)
        }
    }

    var memorySaverCustomDeactivationDelay: TimeInterval {
        didSet {
            let clamped = SumiMemorySaverCustomDelay.clamped(memorySaverCustomDeactivationDelay)
            if clamped != memorySaverCustomDeactivationDelay {
                memorySaverCustomDeactivationDelay = clamped
                return
            }
            userDefaults.set(memorySaverCustomDeactivationDelay, forKey: memorySaverCustomDeactivationDelayKey)
            NotificationCenter.default.post(name: .sumiMemorySaverPolicyChanged, object: nil)
        }
    }

    var startupMode: SumiStartupMode {
        didSet {
            userDefaults.set(startupMode.rawValue, forKey: startupModeKey)
        }
    }

    var startupPageURLString: String {
        didSet {
            userDefaults.set(startupPageURLString, forKey: startupPageURLStringKey)
        }
    }

    var resolvedStartupPageURL: URL {
        SumiStartupPageURL.runtimeURL(from: startupPageURLString)
    }

    init(
        userDefaults: UserDefaults = .standard
    ) {
        self.userDefaults = userDefaults

        // Register default values
        userDefaults.register(defaults: [
            windowSchemeModeKey: WindowSchemeMode.auto.rawValue,
            themeUseSystemColorsKey: false,
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
            showSidebarToggleButtonKey: true,
            showNewTabButtonInTabListKey: true,
            tabListNewTabButtonPositionKey: TabListNewTabButtonPosition.bottom.rawValue,
            showLinkStatusBarKey: true,
            didFinishOnboardingKey: true,
            tabLayoutKey: TabLayout.sidebar.rawValue,
            memoryModeKey: SumiMemoryMode.balanced.rawValue,
            memorySaverCustomDeactivationDelayKey: SumiMemorySaverCustomDelay.defaultDelay,
            startupModeKey: SumiStartupMode.restorePreviousSession.rawValue,
            startupPageURLStringKey: SumiStartupPageURL.defaultURLString,
        ])

        // Initialize properties from UserDefaults
        // This will use the registered defaults if no value is set
        self.windowSchemeMode = WindowSchemeMode(
            rawValue: userDefaults.string(forKey: windowSchemeModeKey) ?? WindowSchemeMode.auto.rawValue
        ) ?? .auto
        self.themeUseSystemColors = userDefaults.bool(forKey: themeUseSystemColorsKey)
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
        self.tabLayout = TabLayout(rawValue: userDefaults.string(forKey: tabLayoutKey) ?? TabLayout.sidebar.rawValue) ?? .sidebar
        self.didFinishOnboarding = userDefaults.bool(forKey: didFinishOnboardingKey)
        let storedMemoryMode = userDefaults.string(forKey: memoryModeKey)
        let resolvedMemoryMode = SumiMemoryMode.persistedValue(storedMemoryMode)
        self.memoryMode = resolvedMemoryMode
        if storedMemoryMode != resolvedMemoryMode.rawValue {
            userDefaults.set(resolvedMemoryMode.rawValue, forKey: memoryModeKey)
        }
        let storedCustomDelay: TimeInterval? = userDefaults.object(forKey: memorySaverCustomDeactivationDelayKey) == nil
            ? nil
            : userDefaults.double(forKey: memorySaverCustomDeactivationDelayKey)
        let resolvedCustomDelay = SumiMemorySaverCustomDelay.validatedOrDefault(
            storedCustomDelay
        )
        self.memorySaverCustomDeactivationDelay = resolvedCustomDelay
        if storedCustomDelay != resolvedCustomDelay {
            userDefaults.set(resolvedCustomDelay, forKey: memorySaverCustomDeactivationDelayKey)
        }
        let storedStartupMode = userDefaults.string(forKey: startupModeKey)
        let resolvedStartupMode = SumiStartupMode.persistedValue(storedStartupMode)
        self.startupMode = resolvedStartupMode
        if storedStartupMode != resolvedStartupMode.rawValue {
            userDefaults.set(resolvedStartupMode.rawValue, forKey: startupModeKey)
        }
        self.startupPageURLString =
            userDefaults.string(forKey: startupPageURLStringKey)
            ?? SumiStartupPageURL.defaultURLString

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
                if tab == .privacy {
                    privacySettingsRoute = Self.privacyRoute(from: url)
                }
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
        if currentSettingsTab == .privacy {
            switch privacySettingsRoute {
            case .overview:
                return currentSettingsTab.settingsSurfaceURL
            case .siteSettings(let filter):
                return SumiSurface.settingsSurfaceURL(
                    paneQuery: SettingsTabs.privacy.paneQueryValue,
                    extraQueryItems: Self.privacySiteSettingsQueryItems(filter: filter)
                )
            }
        }
        return currentSettingsTab.settingsSurfaceURL
    }

    private static func privacyRoute(from url: URL) -> SumiPrivacySettingsRoute {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let section = queryItems.first(where: { $0.name == "section" })?.value?.lowercased()
        guard section == "sitesettings" || section == "site-settings" else {
            return .overview
        }
        let filter = SumiSettingsSiteSettingsFilter(
            requestingOriginIdentity: queryItems.first(where: { $0.name == "origin" })?.value,
            topOriginIdentity: queryItems.first(where: { $0.name == "topOrigin" })?.value,
            displayDomain: queryItems.first(where: { $0.name == "site" })?.value
        )
        return .siteSettings(filter)
    }

    private static func privacySiteSettingsQueryItems(
        filter: SumiSettingsSiteSettingsFilter?
    ) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "section", value: "siteSettings")]
        if let filter {
            if let origin = filter.requestingOriginIdentity, !origin.isEmpty {
                items.append(URLQueryItem(name: "origin", value: origin))
            }
            if let topOrigin = filter.topOriginIdentity, !topOrigin.isEmpty {
                items.append(URLQueryItem(name: "topOrigin", value: topOrigin))
            }
            if let site = filter.displayDomain, !site.isEmpty {
                items.append(URLQueryItem(name: "site", value: site))
            }
        }
        return items
    }

    private func enforceSumiChromeDefaults() {
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
    static let minimum: TimeInterval = 15 * 60
    static let maximum: TimeInterval = 24 * 60 * 60
    static let defaultDelay: TimeInterval = 4 * 60 * 60

    static func clamped(_ delay: TimeInterval) -> TimeInterval {
        guard delay.isFinite, delay > 0 else { return defaultDelay }
        return min(max(delay, minimum), maximum)
    }

    static func validatedOrDefault(_ delay: TimeInterval?) -> TimeInterval {
        guard let delay, delay.isFinite, delay > 0 else { return defaultDelay }
        return clamped(delay)
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

// MARK: - Notification Names
extension Notification.Name {
    static let tabUnloadTimeoutChanged = Notification.Name("tabUnloadTimeoutChanged")
    static let sumiMemorySaverPolicyChanged = Notification.Name("SumiMemorySaverPolicyChanged")
    static let sumiMemoryPressureReceived = Notification.Name("SumiMemoryPressureReceived")
}

// MARK: - Environment Key
private struct SumiSettingsServiceKey: @MainActor EnvironmentKey {
    static var defaultValue: SumiSettingsService {
        // SwiftUI's EnvironmentKey.defaultValue witness is synchronous and
        // nonisolated even though all app access to this key is UI/main-actor
        // bound. Keep the fallback construction on the main actor without
        // making SumiSettingsService Sendable or eager.
        MainActor.assumeIsolated {
            SumiSettingsService()
        }
    }
}

extension EnvironmentValues {
    @MainActor
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
