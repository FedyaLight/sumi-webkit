//
//  BrowserConfig.swift
//  Sumi
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import AppKit
import SwiftUI
import WebKit

enum BrowserConfigurationAuxiliarySurface: String {
    case peek
    case miniWindow
    case extensionOptions
}

class BrowserConfiguration {
    static let shared = BrowserConfiguration()

    private let sharedProcessPool = WKProcessPool()

    init() {}

    private func makeBaseWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.processPool = sharedProcessPool
        config.writingToolsBehavior = .none

        // Match Nook: the shared template configuration uses the default store.
        // Real browser tabs still override this with their profile-specific store,
        // but extension/background plumbing inherits the same baseline behavior.
        config.websiteDataStore = WKWebsiteDataStore.default()

        // Configure JavaScript preferences for extension support
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        // Core WebKit preferences for extensions
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        SumiSetMediaSessionEnabled(config.preferences, true)

        // Media settings
        config.mediaTypesRequiringUserActionForPlayback = []

        // Enable media and fullscreen capabilities on the shared template.
        config.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
        config.preferences.setValue(true, forKey: "mediaDevicesEnabled")
        config.preferences.isElementFullscreenEnabled = true

        // Enable background media playback
        config.allowsAirPlayForMediaPlayback = true

        // Safari parity: match Nook's application UA token so WebKit client hints
        // and UA-based code paths stay aligned between the two browsers.
        config.applicationNameForUserAgent =
            SumiUserAgent.duckDuckGoApplicationNameForUserAgent
        
        config.preferences.setValue(
            RuntimeDiagnostics.isDeveloperInspectionEnabled,
            forKey: "developerExtrasEnabled"
        )

        // Note: WebAuthn/Passkey support is enabled by default in WKWebView on macOS 13.3+
        // and requires only: entitlements, WKUIDelegate methods, and Info.plist descriptions

        return config
    }

    lazy var webViewConfiguration: WKWebViewConfiguration = {
        makeBaseWebViewConfiguration()
    }()

    var normalTabProcessPool: WKProcessPool {
        sharedProcessPool
    }

    // MARK: - Normal Tab Configuration

    @MainActor
    func normalTabWebViewConfiguration(
        for profile: Profile,
        url: URL?,
        userScriptsProvider: SumiNormalTabUserScripts? = nil
    ) -> WKWebViewConfiguration {
        let config = makeBaseWebViewConfiguration()
        config.websiteDataStore = profile.dataStore
        config.userContentController = SumiNormalTabUserContentControllerFactory
            .makeController(
                scriptsProvider: userScriptsProvider,
                profileId: profile.id
            )
        applyMediaSessionPolicy(to: config, profile: profile)
        applySitePermissionOverrides(to: config, url: url, profileId: profile.id)
        return config
    }

    // MARK: - Auxiliary Surface Configuration

    /// Auxiliary WebViews are intentionally separate from primary normal tabs:
    /// popup WebViews come from WebKit, Peek/MiniWindow use lightweight wrappers,
    /// and extension option pages may start from WebKit extension context config.
    @MainActor
    func auxiliaryWebViewConfiguration(
        from source: WKWebViewConfiguration? = nil,
        for profile: Profile? = nil,
        surface: BrowserConfigurationAuxiliarySurface,
        additionalUserScripts: [WKUserScript] = []
    ) -> WKWebViewConfiguration {
        let config = makeBaseWebViewConfiguration()
        config.websiteDataStore =
            profile?.dataStore
            ?? source?.websiteDataStore
            ?? webViewConfiguration.websiteDataStore
        config.userContentController = SumiNormalTabUserContentControllerFactory
            .makeController(
                scriptsProvider: SumiNormalTabUserScripts(),
                profileId: profile?.id
            )
        additionalUserScripts.forEach(config.userContentController.addUserScript)

        if let source {
            config.webExtensionController = source.webExtensionController
        }

        switch surface {
        case .peek, .miniWindow, .extensionOptions:
            break
        }

        applyMediaSessionPolicy(to: config, profile: profile)
        return config
    }

    // MARK: - Cache-Optimized Configuration
    // Auxiliary compatibility path for non-primary surfaces that still request a
    // generic browser-like WebView configuration. This is not a normal-tab
    // creation API and intentionally uses the mini-window auxiliary surface.
    func cacheOptimizedWebViewConfiguration() -> WKWebViewConfiguration {
        MainActor.assumeIsolated {
            auxiliaryWebViewConfiguration(surface: .miniWindow)
        }
    }

    // MARK: - Profile-Aware Configurations
    @MainActor
    func webViewConfiguration(for profile: Profile) -> WKWebViewConfiguration {
        normalTabWebViewConfiguration(for: profile, url: nil)
    }

    @MainActor
    func applyMediaSessionPolicy(
        to configuration: WKWebViewConfiguration,
        profile: Profile?
    ) {
        let isMediaSessionEnabled = profile?.dataStore.isPersistent ?? true
        SumiSetMediaSessionEnabled(
            configuration.preferences,
            isMediaSessionEnabled
        )
    }

    func applySitePermissionOverrides(
        to configuration: WKWebViewConfiguration,
        url: URL?,
        profileId: UUID?
    ) {
        let autoplayState = SitePermissionOverridesStore.shared.autoplayState(
            for: url,
            profileId: profileId
        )
        configuration.mediaTypesRequiringUserActionForPlayback =
            autoplayState == .block ? .all : []
    }
}

enum AutoplayOverrideState: String, Codable, Equatable {
    case allow
    case block

    var subtitle: String {
        switch self {
        case .allow:
            return "Allow"
        case .block:
            return "Block"
        }
    }

    var chromeIconName: String {
        // Zen uses the filled permission glyph for the settings row.
        "autoplay-media-fill"
    }
}

final class SitePermissionOverridesStore {
    static let shared = SitePermissionOverridesStore()

    private let userDefaults = UserDefaults.standard
    private let autoplayOverridesKey = "settings.sitePermissionOverrides.autoplay"
    private var autoplayOverrides: [String: [String: AutoplayOverrideState]]

    private init() {
        autoplayOverrides = Self.loadOverrides(
            key: autoplayOverridesKey,
            userDefaults: userDefaults
        )
    }

    func autoplayState(for url: URL?, profileId: UUID?) -> AutoplayOverrideState {
        guard
            let profileKey = normalizedProfileKey(profileId),
            let host = normalizedHost(for: url)
        else {
            return .allow
        }

        return autoplayOverrides[profileKey]?[host] ?? .allow
    }

    func hasAutoplayOverride(for url: URL?, profileId: UUID?) -> Bool {
        guard
            let profileKey = normalizedProfileKey(profileId),
            let host = normalizedHost(for: url)
        else {
            return false
        }

        return autoplayOverrides[profileKey]?[host] != nil
    }

    func toggleAutoplay(for url: URL?, profileId: UUID?) -> AutoplayOverrideState {
        let nextState: AutoplayOverrideState = autoplayState(
            for: url,
            profileId: profileId
        ) == .allow ? .block : .allow
        setAutoplayState(nextState, for: url, profileId: profileId)
        return nextState
    }

    func setAutoplayState(
        _ state: AutoplayOverrideState,
        for url: URL?,
        profileId: UUID?
    ) {
        guard
            let profileKey = normalizedProfileKey(profileId),
            let host = normalizedHost(for: url)
        else {
            return
        }

        var profileOverrides = autoplayOverrides[profileKey] ?? [:]
        profileOverrides[host] = state
        autoplayOverrides[profileKey] = profileOverrides
        persistAutoplayOverrides()
    }

    private func persistAutoplayOverrides() {
        guard let data = try? JSONEncoder().encode(autoplayOverrides) else {
            return
        }
        userDefaults.set(data, forKey: autoplayOverridesKey)
    }

    private func normalizedProfileKey(_ profileId: UUID?) -> String? {
        profileId?.uuidString.lowercased()
    }

    private func normalizedHost(for url: URL?) -> String? {
        url?.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func loadOverrides(
        key: String,
        userDefaults: UserDefaults
    ) -> [String: [String: AutoplayOverrideState]] {
        guard
            let data = userDefaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(
                [String: [String: AutoplayOverrideState]].self,
                from: data
            )
        else {
            return [:]
        }
        return decoded
    }
}
