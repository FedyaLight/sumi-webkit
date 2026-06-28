//
//  SumiSettingsService.swift
//  Sumi
//
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
    private let sidebarMiniPlayerEnabledKey = "settings.sidebarMiniPlayerEnabled"
    private let glanceEnabledKey = "settings.glanceEnabled"
    private let showSidebarToggleButtonKey = "settings.showSidebarToggleButton"
    private let showNewTabButtonInTabListKey = "settings.showNewTabButtonInTabList"
    private let tabListNewTabButtonPositionKey = "settings.tabListNewTabButtonPosition"
    private let showLinkStatusBarKey = "settings.showLinkStatusBar"
    private let showBrowserToastsKey = "settings.showBrowserToasts"
    private let framelessChromeKey = "settings.framelessChrome"
    private let searchEnginesKey = "settings.searchEngines"
    private let floatingBarEmptyStateModeKey = "settings.floatingBar.emptyStateMode"
    private let newTabModeKey = "settings.newTabMode"
    private let newTabPageURLStringKey = "settings.newTab.pageURL"
    private let didFinishOnboardingKey = "settings.didFinishOnboarding"
    private let memoryModeKey = "settings.memoryMode"
    private let memorySaverCustomDeactivationDelayKey = "settings.memorySaver.customDeactivationDelay"
    private let energySaverModeKey = "settings.energySaver.mode"
    private let energySaverBatteryThresholdKey = "settings.energySaver.batteryThreshold"
    private let energySaverFeaturesKey = "settings.energySaver.features"
    private let startupModeKey = "settings.startup.mode"
    private let startupPageURLStringKey = "settings.startup.pageURL"
    private let browsingDataRetentionDaysKey = "settings.browsingData.retentionDays"
    private let downloadsAlwaysAskWhereToSaveKey = "settings.downloads.alwaysAskWhereToSave"
    private let downloadsDirectoryBookmarkKey = "settings.downloads.directoryBookmark"
    private let downloadsDirectoryPathKey = "settings.downloads.directoryPath"
    private let downloadsFallbackActionKey = "settings.downloads.fallbackAction"
    private let energySaverSystemMonitor: any SumiEnergySaverSystemMonitoring
    @ObservationIgnored
    nonisolated(unsafe) private var energySaverSystemObservationToken: UUID?

    var currentSettingsTab: SettingsTabs = .general

    var privacySettingsRoute: SumiPrivacySettingsRoute = .overview
    let downloadApplicationsStore: SumiDownloadApplicationsStore

    /// Extensions vs SumiScripts, when `currentSettingsTab == .extensions`.
    var extensionsSettingsSubPane: SumiExtensionsSettingsSubPane = .extensions

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

    var searchEngines: [SumiSearchEngine] {
        didSet {
            let normalized = SumiSearchEngine.normalized(searchEngines)
            if normalized != searchEngines {
                searchEngines = normalized
                return
            }

            if let data = try? JSONEncoder().encode(searchEngines) {
                userDefaults.set(data, forKey: searchEnginesKey)
            }

            if !searchEngines.contains(where: { $0.id == searchEngineId }) {
                searchEngineId = SumiSearchEngine.defaultSearchEngineID(in: searchEngines)
            }
        }
    }

    /// Resolves the current `searchEngineId` to a query template string.
    var resolvedSearchEngineTemplate: String {
        if let engine = searchEngines.first(where: { $0.id == searchEngineId }) {
            return engine.queryTemplate
        }
        return SearchProvider.google.queryTemplate
    }

    var resolvedSearchEngineDisplayName: String {
        if let engine = searchEngines.first(where: { $0.id == searchEngineId }) {
            return engine.name
        }
        return SearchProvider.google.displayName
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

    var sidebarMiniPlayerEnabled: Bool {
        didSet {
            userDefaults.set(sidebarMiniPlayerEnabled, forKey: sidebarMiniPlayerEnabledKey)
            SumiNativeNowPlayingController.shared.setFeatureEnabled(sidebarMiniPlayerEnabled)
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

    var showBrowserToasts: Bool {
        didSet {
            userDefaults.set(showBrowserToasts, forKey: showBrowserToastsKey)
        }
    }

    /// Removes the side and bottom window frame around web content, extending
    /// it edge-to-edge while keeping the top bar gap and the sidebar.
    var framelessChrome: Bool {
        didSet {
            userDefaults.set(framelessChrome, forKey: framelessChromeKey)
        }
    }

    var floatingBarEmptyStateMode: FloatingBarEmptyStateMode {
        didSet {
            userDefaults.set(floatingBarEmptyStateMode.rawValue, forKey: floatingBarEmptyStateModeKey)
        }
    }

    var newTabMode: SumiNewTabMode {
        didSet {
            userDefaults.set(newTabMode.rawValue, forKey: newTabModeKey)
        }
    }

    var newTabPageURLString: String {
        didSet {
            userDefaults.set(newTabPageURLString, forKey: newTabPageURLStringKey)
        }
    }

    var resolvedNewTabPageURL: URL {
        SumiNewTabPageURL.runtimeURL(from: newTabPageURLString)
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
            let normalized = SumiMemorySaverCustomDelay.nearestPreset(
                to: memorySaverCustomDeactivationDelay
            )
            if normalized != memorySaverCustomDeactivationDelay {
                memorySaverCustomDeactivationDelay = normalized
                return
            }
            userDefaults.set(memorySaverCustomDeactivationDelay, forKey: memorySaverCustomDeactivationDelayKey)
            NotificationCenter.default.post(name: .sumiMemorySaverPolicyChanged, object: nil)
        }
    }

    var energySaverMode: SumiEnergySaverMode {
        didSet {
            userDefaults.set(energySaverMode.rawValue, forKey: energySaverModeKey)
            notifyEnergySaverPolicyChanged()
        }
    }

    var energySaverBatteryThreshold: Int {
        didSet {
            let clamped = SumiEnergySaverPolicy.clampedBatteryThreshold(energySaverBatteryThreshold)
            if clamped != energySaverBatteryThreshold {
                energySaverBatteryThreshold = clamped
                return
            }
            userDefaults.set(energySaverBatteryThreshold, forKey: energySaverBatteryThresholdKey)
            notifyEnergySaverPolicyChanged()
        }
    }

    var energySaverFeatures: Set<SumiEnergySaverFeature> {
        didSet {
            userDefaults.set(
                energySaverFeatures.map(\.rawValue).sorted(),
                forKey: energySaverFeaturesKey
            )
            notifyEnergySaverPolicyChanged()
        }
    }

    private(set) var energySaverSystemSnapshot: SumiEnergySaverSystemSnapshot {
        didSet {
            guard energySaverSystemSnapshot != oldValue else { return }
            notifyEnergySaverPolicyChanged()
        }
    }

    var energySaverActivation: SumiEnergySaverActivation {
        SumiEnergySaverPolicy.activation(
            mode: energySaverMode,
            batteryThreshold: energySaverBatteryThreshold,
            snapshot: energySaverSystemSnapshot
        )
    }

    func energySaverApplies(_ feature: SumiEnergySaverFeature) -> Bool {
        energySaverActivation.isActive && energySaverFeatures.contains(feature)
    }

    var shouldReduceChromeMotion: Bool {
        energySaverApplies(.reduceInterfaceAnimations)
    }

    var shouldUseOpaqueChromeSurfaces: Bool {
        energySaverApplies(.useOpaqueChromeSurfaces)
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

    var browsingDataRetentionPeriod: SumiBrowsingDataRetentionPeriod {
        didSet {
            userDefaults.set(browsingDataRetentionPeriod.rawValue, forKey: browsingDataRetentionDaysKey)
            NotificationCenter.default.post(
                name: .sumiBrowsingDataRetentionChanged,
                object: nil,
                userInfo: ["days": browsingDataRetentionPeriod.rawValue]
            )
        }
    }

    var downloadsAlwaysAskWhereToSave: Bool {
        didSet {
            userDefaults.set(downloadsAlwaysAskWhereToSave, forKey: downloadsAlwaysAskWhereToSaveKey)
        }
    }

    private(set) var downloadsDirectoryURL: URL? {
        didSet {
            userDefaults.set(downloadsDirectoryURL?.path, forKey: downloadsDirectoryPathKey)
        }
    }

    var downloadsFallbackAction: SumiDownloadFallbackAction {
        didSet {
            userDefaults.set(downloadsFallbackAction.rawValue, forKey: downloadsFallbackActionKey)
        }
    }

    var downloadsDestinationPreference: SumiDownloadDestinationPreference {
        SumiDownloadDestinationPreference(
            alwaysAskWhereToSave: DownloadsDirectoryResolver.usesIsolatedDirectory
                ? false
                : downloadsAlwaysAskWhereToSave,
            customDirectoryURL: resolvedDownloadsDirectoryURL()
        )
    }

    var downloadsDirectoryDisplayName: String {
        let url = resolvedDownloadsDirectoryURL() ?? DownloadsDirectoryResolver.resolvedDownloadsDirectory()
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    func setDownloadsDirectory(_ url: URL) {
        guard !DownloadsDirectoryResolver.usesIsolatedDirectory else {
            downloadsDirectoryURL = url
            return
        }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            userDefaults.set(bookmark, forKey: downloadsDirectoryBookmarkKey)
            downloadsDirectoryURL = url
        } catch {
            RuntimeDiagnostics.debug(
                "Failed to save downloads directory bookmark: \(String(describing: error))",
                category: "DownloadManager"
            )
        }
    }

    func clearDownloadsDirectory() {
        userDefaults.removeObject(forKey: downloadsDirectoryBookmarkKey)
        userDefaults.removeObject(forKey: downloadsDirectoryPathKey)
        downloadsDirectoryURL = nil
    }

    func resolvedDownloadsDirectoryURL() -> URL? {
        guard !DownloadsDirectoryResolver.usesIsolatedDirectory else {
            return nil
        }
        guard let bookmark = userDefaults.data(forKey: downloadsDirectoryBookmarkKey) else {
            return downloadsDirectoryURL
        }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                setDownloadsDirectory(url)
            }
            return url
        } catch {
            return downloadsDirectoryURL
        }
    }

    var resolvedStartupPageURL: URL {
        SumiStartupPageURL.runtimeURL(from: startupPageURLString)
    }

    init(
        userDefaults: UserDefaults = .standard,
        energySaverSystemMonitor: any SumiEnergySaverSystemMonitoring =
            SumiEnergySaverSystemMonitor.shared,
        downloadApplicationsStore: SumiDownloadApplicationsStore = SumiDownloadApplicationsStore()
    ) {
        self.userDefaults = userDefaults
        self.energySaverSystemMonitor = energySaverSystemMonitor
        self.downloadApplicationsStore = downloadApplicationsStore

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
            sidebarMiniPlayerEnabledKey: true,
            glanceEnabledKey: true,
            showSidebarToggleButtonKey: true,
            showNewTabButtonInTabListKey: true,
            tabListNewTabButtonPositionKey: TabListNewTabButtonPosition.bottom.rawValue,
            showLinkStatusBarKey: true,
            showBrowserToastsKey: true,
            framelessChromeKey: false,
            floatingBarEmptyStateModeKey: FloatingBarEmptyStateMode.compact.rawValue,
            newTabModeKey: SumiNewTabMode.floatingBar.rawValue,
            newTabPageURLStringKey: SumiNewTabPageURL.defaultURLString,
            didFinishOnboardingKey: true,
            memoryModeKey: SumiMemoryMode.balanced.rawValue,
            memorySaverCustomDeactivationDelayKey: SumiMemorySaverCustomDelay.defaultDelay,
            energySaverModeKey: SumiEnergySaverMode.automatic.rawValue,
            energySaverBatteryThresholdKey: SumiEnergySaverPolicy.defaultBatteryThreshold,
            energySaverFeaturesKey: SumiEnergySaverFeature.defaultSelection.map(\.rawValue).sorted(),
            startupModeKey: SumiStartupMode.restorePreviousSession.rawValue,
            startupPageURLStringKey: SumiStartupPageURL.defaultURLString,
            browsingDataRetentionDaysKey: SumiBrowsingDataRetentionPeriod.defaultPeriod.rawValue,
            downloadsAlwaysAskWhereToSaveKey: false,
            downloadsFallbackActionKey: SumiDownloadFallbackAction.saveFile.rawValue,
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

        let storedSearchEngineID = userDefaults.string(forKey: searchEngineKey) ?? SearchProvider.google.rawValue
        self.searchEngineId = storedSearchEngineID

        // Initialize tab unload timeout
        self.tabUnloadTimeout = userDefaults.double(forKey: tabUnloadTimeoutKey)
        self.askBeforeQuit = userDefaults.bool(forKey: askBeforeQuitKey)
        self.sidebarPosition = SidebarPosition(rawValue: userDefaults.string(forKey: sidebarPositionKey) ?? "left") ?? SidebarPosition.left
        self.sidebarCompactSpaces = userDefaults.bool(forKey: sidebarCompactSpacesKey)
        if userDefaults.object(forKey: sidebarMiniPlayerEnabledKey) == nil {
            self.sidebarMiniPlayerEnabled = true
        } else {
            self.sidebarMiniPlayerEnabled = userDefaults.bool(forKey: sidebarMiniPlayerEnabledKey)
        }
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
        self.showBrowserToasts = userDefaults.bool(forKey: showBrowserToastsKey)
        self.framelessChrome = userDefaults.bool(forKey: framelessChromeKey)
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
        self.energySaverMode = SumiEnergySaverMode(
            rawValue: userDefaults.string(forKey: energySaverModeKey)
                ?? SumiEnergySaverMode.automatic.rawValue
        ) ?? .automatic
        let storedEnergySaverBatteryThreshold = userDefaults.integer(
            forKey: energySaverBatteryThresholdKey
        )
        let resolvedEnergySaverBatteryThreshold = SumiEnergySaverPolicy.clampedBatteryThreshold(
            storedEnergySaverBatteryThreshold
        )
        self.energySaverBatteryThreshold = resolvedEnergySaverBatteryThreshold
        if storedEnergySaverBatteryThreshold != resolvedEnergySaverBatteryThreshold {
            userDefaults.set(
                resolvedEnergySaverBatteryThreshold,
                forKey: energySaverBatteryThresholdKey
            )
        }
        self.energySaverFeatures = Set(
            (userDefaults.stringArray(forKey: energySaverFeaturesKey) ?? [])
                .compactMap(SumiEnergySaverFeature.init(rawValue:))
        )
        self.energySaverSystemSnapshot = energySaverSystemMonitor.snapshot
        let storedStartupMode = userDefaults.string(forKey: startupModeKey)
        let resolvedStartupMode = SumiStartupMode.persistedValue(storedStartupMode)
        self.startupMode = resolvedStartupMode
        if storedStartupMode != resolvedStartupMode.rawValue {
            userDefaults.set(resolvedStartupMode.rawValue, forKey: startupModeKey)
        }
        self.startupPageURLString =
            userDefaults.string(forKey: startupPageURLStringKey)
            ?? SumiStartupPageURL.defaultURLString
        let storedBrowsingDataRetentionDays = userDefaults.object(
            forKey: browsingDataRetentionDaysKey
        ) as? Int
        let resolvedBrowsingDataRetentionPeriod = SumiBrowsingDataRetentionPeriod.persistedValue(
            storedBrowsingDataRetentionDays
        )
        self.browsingDataRetentionPeriod = resolvedBrowsingDataRetentionPeriod
        if storedBrowsingDataRetentionDays != resolvedBrowsingDataRetentionPeriod.rawValue {
            userDefaults.set(
                resolvedBrowsingDataRetentionPeriod.rawValue,
                forKey: browsingDataRetentionDaysKey
            )
        }
        self.downloadsAlwaysAskWhereToSave = userDefaults.bool(forKey: downloadsAlwaysAskWhereToSaveKey)
        self.downloadsDirectoryURL = userDefaults.string(forKey: downloadsDirectoryPathKey).flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
        }
        self.downloadsFallbackAction = SumiDownloadFallbackAction(
            rawValue: userDefaults.string(forKey: downloadsFallbackActionKey)
                ?? SumiDownloadFallbackAction.saveFile.rawValue
        ) ?? .saveFile

        let loadedSearchEngines: [SumiSearchEngine]
        if let data = userDefaults.data(forKey: searchEnginesKey),
           let decoded = try? JSONDecoder().decode([SumiSearchEngine].self, from: data),
           decoded.isEmpty == false {
            loadedSearchEngines = SumiSearchEngine.normalized(decoded)
        } else {
            loadedSearchEngines = SumiSearchEngine.defaultEngines()
        }
        self.searchEngines = loadedSearchEngines

        if !loadedSearchEngines.contains(where: { $0.id == storedSearchEngineID }) {
            self.searchEngineId = SumiSearchEngine.defaultSearchEngineID(in: loadedSearchEngines)
        }

        self.floatingBarEmptyStateMode = FloatingBarEmptyStateMode(
            rawValue: userDefaults.string(forKey: floatingBarEmptyStateModeKey) ?? FloatingBarEmptyStateMode.compact.rawValue
        ) ?? .compact

        let storedNewTabMode = userDefaults.string(forKey: newTabModeKey)
        let resolvedNewTabMode = SumiNewTabMode.persistedValue(storedNewTabMode)
        self.newTabMode = resolvedNewTabMode
        if storedNewTabMode != resolvedNewTabMode.rawValue {
            userDefaults.set(resolvedNewTabMode.rawValue, forKey: newTabModeKey)
        }
        self.newTabPageURLString =
            userDefaults.string(forKey: newTabPageURLStringKey)
            ?? SumiNewTabPageURL.defaultURLString

        enforceSumiChromeDefaults()
        SumiNativeNowPlayingController.shared.setFeatureEnabled(sidebarMiniPlayerEnabled)
        energySaverSystemObservationToken = energySaverSystemMonitor.addObserver {
            [weak self] snapshot in
            self?.energySaverSystemSnapshot = snapshot
        }
    }

    deinit {
        let monitor = energySaverSystemMonitor
        if let token = energySaverSystemObservationToken {
            Task { @MainActor in
                monitor.removeObserver(token)
            }
        }
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
            extensionsSettingsSubPane = .extensions
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
            case .extensions:
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
        if !didFinishOnboarding {
            didFinishOnboarding = true
        }
    }

    private func notifyEnergySaverPolicyChanged() {
        NotificationCenter.default.post(name: .sumiEnergySaverPolicyChanged, object: self)
    }
}

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
