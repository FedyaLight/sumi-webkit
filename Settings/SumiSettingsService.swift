//
//  SumiSettingsService.swift
//  Sumi
//
//

import SwiftUI
import SumiDomain

@MainActor
@Observable
class SumiSettingsService {
    private let nowPlayingController: any SumiNativeNowPlayingFeatureControlling

    // MARK: - Domain stores (Phase 5F)

    let theme: ThemeSettingsStore
    let search: SearchSettingsStore
    let chrome: ChromeLayoutSettingsStore
    let performance: PerformanceSettingsStore
    let startupPrivacy: StartupPrivacySettingsStore
    let downloads: DownloadSettingsStore

    /// Owns settings-surface UI routing (selected pane, privacy route, sub-pane,
    /// and URL translation). Kept separate from preference persistence.
    let navigation = SettingsNavigationOwner()

    var currentSettingsTab: SettingsTabs {
        get { navigation.currentSettingsTab }
        set { navigation.currentSettingsTab = newValue }
    }

    var privacySettingsRoute: SumiPrivacySettingsRoute {
        get { navigation.privacySettingsRoute }
        set { navigation.privacySettingsRoute = newValue }
    }

    // MARK: - Theme façade

    var windowSchemeMode: WindowSchemeMode {
        get { theme.windowSchemeMode }
        set { theme.windowSchemeMode = newValue }
    }

    var themeUseSystemColors: Bool {
        get { theme.themeUseSystemColors }
        set { theme.themeUseSystemColors = newValue }
    }

    var themeBorderRadius: Int {
        get { theme.themeBorderRadius }
        set { theme.themeBorderRadius = newValue }
    }

    var darkThemeStyle: DarkThemeStyle {
        get { theme.darkThemeStyle }
        set { theme.darkThemeStyle = newValue }
    }

    func resolvedCornerRadius(_ fallback: CGFloat) -> CGFloat {
        theme.resolvedCornerRadius(fallback)
    }

    // MARK: - Search façade

    var searchEngineId: String {
        get { search.searchEngineId }
        set { search.searchEngineId = newValue }
    }

    var searchEngines: [SumiSearchEngine] {
        get { search.searchEngines }
        set { search.searchEngines = newValue }
    }

    var resolvedSearchEngineTemplate: String {
        search.resolvedSearchEngineTemplate
    }

    var resolvedSearchEngineDisplayName: String {
        search.resolvedSearchEngineDisplayName
    }

    // MARK: - Chrome layout façade

    var askBeforeQuit: Bool {
        get { chrome.askBeforeQuit }
        set { chrome.askBeforeQuit = newValue }
    }

    var sidebarPosition: SidebarPosition {
        get { chrome.sidebarPosition }
        set { chrome.sidebarPosition = newValue }
    }

    var sidebarMiniPlayerEnabled: Bool {
        get { chrome.sidebarMiniPlayerEnabled }
        set { chrome.sidebarMiniPlayerEnabled = newValue }
    }

    var glanceEnabled: Bool {
        get { chrome.glanceEnabled }
        set { chrome.glanceEnabled = newValue }
    }

    var showSidebarToggleButton: Bool {
        get { chrome.showSidebarToggleButton }
        set { chrome.showSidebarToggleButton = newValue }
    }

    var showNewTabButtonInTabList: Bool {
        get { chrome.showNewTabButtonInTabList }
        set { chrome.showNewTabButtonInTabList = newValue }
    }

    var tabListNewTabButtonPosition: TabListNewTabButtonPosition {
        get { chrome.tabListNewTabButtonPosition }
        set { chrome.tabListNewTabButtonPosition = newValue }
    }

    var showLinkStatusBar: Bool {
        get { chrome.showLinkStatusBar }
        set { chrome.showLinkStatusBar = newValue }
    }

    var showInAppNotifications: Bool {
        get { chrome.showInAppNotifications }
        set { chrome.showInAppNotifications = newValue }
    }

    /// Removes the side and bottom window frame around web content, extending
    /// it edge-to-edge while keeping the top bar gap and the sidebar.
    var framelessChrome: Bool {
        get { chrome.framelessChrome }
        set { chrome.framelessChrome = newValue }
    }

    var floatingBarEmptyStateMode: FloatingBarEmptyStateMode {
        get { chrome.floatingBarEmptyStateMode }
        set { chrome.floatingBarEmptyStateMode = newValue }
    }

    var newTabMode: SumiNewTabMode {
        get { chrome.newTabMode }
        set { chrome.newTabMode = newValue }
    }

    var newTabPageURLString: String {
        get { chrome.newTabPageURLString }
        set { chrome.newTabPageURLString = newValue }
    }

    var resolvedNewTabPageURL: URL {
        chrome.resolvedNewTabPageURL
    }

    var didFinishOnboarding: Bool {
        get { chrome.didFinishOnboarding }
        set { chrome.didFinishOnboarding = newValue }
    }

    // MARK: - Performance façade

    var tabUnloadTimeout: TimeInterval {
        get { performance.tabUnloadTimeout }
        set { performance.tabUnloadTimeout = newValue }
    }

    var memoryMode: SumiMemoryMode {
        get { performance.memoryMode }
        set { performance.memoryMode = newValue }
    }

    var memorySaverCustomDeactivationDelay: TimeInterval {
        get { performance.memorySaverCustomDeactivationDelay }
        set { performance.memorySaverCustomDeactivationDelay = newValue }
    }

    var energySaverMode: SumiEnergySaverMode {
        get { performance.energySaverMode }
        set { performance.energySaverMode = newValue }
    }

    var energySaverBatteryThreshold: Int {
        get { performance.energySaverBatteryThreshold }
        set { performance.energySaverBatteryThreshold = newValue }
    }

    var energySaverFeatures: Set<SumiEnergySaverFeature> {
        get { performance.energySaverFeatures }
        set { performance.energySaverFeatures = newValue }
    }

    var energySaverSystemSnapshot: SumiEnergySaverSystemSnapshot {
        performance.energySaverSystemSnapshot
    }

    var energySaverActivation: SumiEnergySaverActivation {
        performance.energySaverActivation
    }

    func energySaverApplies(_ feature: SumiEnergySaverFeature) -> Bool {
        performance.energySaverApplies(feature)
    }

    var shouldReduceChromeMotion: Bool {
        performance.shouldReduceChromeMotion
    }

    var shouldUseOpaqueChromeSurfaces: Bool {
        performance.shouldUseOpaqueChromeSurfaces
    }

    // MARK: - Startup / privacy façade

    var startupMode: SumiStartupMode {
        get { startupPrivacy.startupMode }
        set { startupPrivacy.startupMode = newValue }
    }

    var startupPageURLString: String {
        get { startupPrivacy.startupPageURLString }
        set { startupPrivacy.startupPageURLString = newValue }
    }

    var browsingDataRetentionPeriod: SumiBrowsingDataRetentionPeriod {
        get { startupPrivacy.browsingDataRetentionPeriod }
        set { startupPrivacy.browsingDataRetentionPeriod = newValue }
    }

    /// Global Privacy Control: broadcasts the user's opt-out of sale/sharing of
    /// personal data to every site, via both a DOM signal and a `Sec-GPC` request
    /// header. On by default, matching Firefox/Brave/DDG's stance that GPC is a
    /// baseline privacy signal rather than an opt-in feature.
    var isGPCEnabled: Bool {
        get { startupPrivacy.isGPCEnabled }
        set { startupPrivacy.isGPCEnabled = newValue }
    }

    var resolvedStartupPageURL: URL {
        startupPrivacy.resolvedStartupPageURL
    }

    // MARK: - Download façade

    var downloadApplicationsStore: SumiDownloadApplicationsStore {
        downloads.downloadApplicationsStore
    }

    var downloadsAlwaysAskWhereToSave: Bool {
        get { downloads.downloadsAlwaysAskWhereToSave }
        set { downloads.downloadsAlwaysAskWhereToSave = newValue }
    }

    var downloadsDirectoryStore: SumiDownloadsDirectoryStore {
        downloads.downloadsDirectoryStore
    }

    var downloadsDirectoryURL: URL? {
        downloads.downloadsDirectoryURL
    }

    var downloadsFallbackAction: SumiDownloadFallbackAction {
        get { downloads.downloadsFallbackAction }
        set { downloads.downloadsFallbackAction = newValue }
    }

    var downloadsDestinationPreference: SumiDownloadDestinationPreference {
        downloads.downloadsDestinationPreference
    }

    var downloadsDirectoryDisplayName: String {
        downloads.downloadsDirectoryDisplayName
    }

    func setDownloadsDirectory(_ url: URL) {
        downloads.setDownloadsDirectory(url)
    }

    func clearDownloadsDirectory() {
        downloads.clearDownloadsDirectory()
    }

    func resolvedDownloadsDirectoryURL() -> URL? {
        downloads.resolvedDownloadsDirectoryURL()
    }

    // MARK: - Init

    init(
        userDefaults: UserDefaults = .standard,
        energySaverSystemMonitor: any SumiEnergySaverSystemMonitoring =
            SumiEnergySaverSystemMonitor(),
        nowPlayingController: any SumiNativeNowPlayingFeatureControlling =
            SumiNativeNowPlayingController(),
        downloadApplicationsStore: SumiDownloadApplicationsStore = SumiDownloadApplicationsStore()
    ) {
        self.nowPlayingController = nowPlayingController

        // Register default values
        userDefaults.register(defaults: [
            "settings.windowSchemeMode": WindowSchemeMode.auto.rawValue,
            "settings.themeUseSystemColors": false,
            "settings.themeBorderRadius": -1,
            "settings.darkThemeStyle": DarkThemeStyle.default.rawValue,
            "settings.searchEngine": SearchProvider.google.rawValue,
            // Default tab unload timeout: 60 minutes
            "settings.tabUnloadTimeout": 3600.0,
            "settings.askBeforeQuit": true,
            "settings.sidebarPosition": SidebarPosition.left.rawValue,
            "settings.sidebarMiniPlayerEnabled": true,
            "settings.glanceEnabled": true,
            "settings.showSidebarToggleButton": true,
            "settings.showNewTabButtonInTabList": true,
            "settings.tabListNewTabButtonPosition": TabListNewTabButtonPosition.bottom.rawValue,
            "settings.showLinkStatusBar": true,
            "settings.showBrowserToasts": true,
            "settings.framelessChrome": false,
            "settings.floatingBar.emptyStateMode": FloatingBarEmptyStateMode.compact.rawValue,
            "settings.newTabMode": SumiNewTabMode.floatingBar.rawValue,
            "settings.newTab.pageURL": SumiNewTabPageURL.defaultURLString,
            "settings.didFinishOnboarding": true,
            "settings.memoryMode": SumiMemoryMode.balanced.rawValue,
            "settings.memorySaver.customDeactivationDelay": SumiMemorySaverCustomDelay.defaultDelay,
            "settings.energySaver.mode": SumiEnergySaverMode.automatic.rawValue,
            "settings.energySaver.batteryThreshold": SumiEnergySaverPolicy.defaultBatteryThreshold,
            "settings.energySaver.features": SumiEnergySaverFeature.defaultSelection.map(\.rawValue).sorted(),
            "settings.startup.mode": SumiStartupMode.restorePreviousSession.rawValue,
            "settings.startup.pageURL": SumiStartupPageURL.defaultURLString,
            "settings.browsingData.retentionDays": SumiBrowsingDataRetentionPeriod.defaultPeriod.rawValue,
            "settings.downloads.alwaysAskWhereToSave": false,
            "settings.downloads.fallbackAction": SumiDownloadFallbackAction.saveFile.rawValue,
            "settings.privacy.gpcEnabled": true,
        ])

        self.theme = ThemeSettingsStore(
            userDefaults: userDefaults,
            windowSchemeModeKey: "settings.windowSchemeMode",
            themeUseSystemColorsKey: "settings.themeUseSystemColors",
            themeBorderRadiusKey: "settings.themeBorderRadius",
            darkThemeStyleKey: "settings.darkThemeStyle"
        )
        self.search = SearchSettingsStore(
            userDefaults: userDefaults,
            searchEngineKey: "settings.searchEngine",
            searchEnginesKey: "settings.searchEngines"
        )
        self.chrome = ChromeLayoutSettingsStore(
            userDefaults: userDefaults,
            askBeforeQuitKey: "settings.askBeforeQuit",
            sidebarPositionKey: "settings.sidebarPosition",
            sidebarMiniPlayerEnabledKey: "settings.sidebarMiniPlayerEnabled",
            glanceEnabledKey: "settings.glanceEnabled",
            showSidebarToggleButtonKey: "settings.showSidebarToggleButton",
            showNewTabButtonInTabListKey: "settings.showNewTabButtonInTabList",
            tabListNewTabButtonPositionKey: "settings.tabListNewTabButtonPosition",
            showLinkStatusBarKey: "settings.showLinkStatusBar",
            showBrowserToastsKey: "settings.showBrowserToasts",
            framelessChromeKey: "settings.framelessChrome",
            floatingBarEmptyStateModeKey: "settings.floatingBar.emptyStateMode",
            newTabModeKey: "settings.newTabMode",
            newTabPageURLStringKey: "settings.newTab.pageURL",
            didFinishOnboardingKey: "settings.didFinishOnboarding",
            onSidebarMiniPlayerEnabledChanged: { enabled in
                nowPlayingController.setFeatureEnabled(enabled)
            }
        )
        self.performance = PerformanceSettingsStore(
            userDefaults: userDefaults,
            tabUnloadTimeoutKey: "settings.tabUnloadTimeout",
            memoryModeKey: "settings.memoryMode",
            memorySaverCustomDeactivationDelayKey: "settings.memorySaver.customDeactivationDelay",
            energySaverModeKey: "settings.energySaver.mode",
            energySaverBatteryThresholdKey: "settings.energySaver.batteryThreshold",
            energySaverFeaturesKey: "settings.energySaver.features",
            energySaverSystemMonitor: energySaverSystemMonitor
        )
        self.startupPrivacy = StartupPrivacySettingsStore(
            userDefaults: userDefaults,
            startupModeKey: "settings.startup.mode",
            startupPageURLStringKey: "settings.startup.pageURL",
            browsingDataRetentionDaysKey: "settings.browsingData.retentionDays",
            gpcEnabledKey: "settings.privacy.gpcEnabled"
        )
        self.downloads = DownloadSettingsStore(
            userDefaults: userDefaults,
            downloadsAlwaysAskWhereToSaveKey: "settings.downloads.alwaysAskWhereToSave",
            downloadsFallbackActionKey: "settings.downloads.fallbackAction",
            downloadApplicationsStore: downloadApplicationsStore
        )

        chrome.enforceSumiChromeDefaults()
        nowPlayingController.setFeatureEnabled(chrome.sidebarMiniPlayerEnabled)
    }

    /// Syncs sidebar state from `sumi://settings?pane=…`.
    func applyNavigationFromSettingsSurfaceURL(_ url: URL) {
        navigation.applyNavigation(from: url)
    }

    /// URL for the active settings tab.
    func settingsSurfaceURLForCurrentNavigation() -> URL {
        navigation.settingsSurfaceURLForCurrentNavigation()
    }
}


// MARK: - Notification Names
extension Notification.Name {
    static let tabUnloadTimeoutChanged = Notification.Name("tabUnloadTimeoutChanged")
    static let sumiMemorySaverPolicyChanged = Notification.Name("SumiMemorySaverPolicyChanged")
    static let sumiMemoryPressureReceived = Notification.Name("SumiMemoryPressureReceived")
    static let sumiEnergySaverPolicyChanged = Notification.Name("SumiEnergySaverPolicyChanged")
    static let sumiBrowsingDataRetentionChanged =
        Notification.Name("SumiBrowsingDataRetentionChanged")
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
