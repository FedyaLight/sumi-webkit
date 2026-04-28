//
//  BrowserConfig.swift
//  Sumi
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import AppKit
import SwiftUI
import WebKit

enum BrowserConfigurationAuxiliarySurface: String, CaseIterable {
    case faviconDownload
    case peek
    case miniWindow
    case extensionOptions

    var allowsJavaScript: Bool {
        switch self {
        case .faviconDownload:
            return false
        case .peek, .miniWindow, .extensionOptions:
            return true
        }
    }

    var javaScriptCanOpenWindowsAutomatically: Bool {
        switch self {
        case .faviconDownload:
            return false
        case .peek, .miniWindow, .extensionOptions:
            return true
        }
    }
}

class BrowserConfiguration {
    static let shared = BrowserConfiguration()

    private let sharedProcessPool = WKProcessPool()
    private let autoplayPolicyStore: SumiAutoplayPolicyStoreAdapter?
    private static let auxiliaryFilteredUserScriptMarkers = [
        "__sumiDDGFaviconTransportInstalled",
        "__sumiTabSuspension",
        "SUMI_USER_SCRIPT_RUNTIME",
        "SUMI_EC_PAGE_BRIDGE:",
        "data-sumi-userscript",
        "sumiExternallyConnectableRuntime",
        "sumiFavicons",
        "sumiGM_",
        "sumiIdentity_",
        "sumiLinkInteraction_",
        "sumiTabSuspension_",
        "sumiWebNotifications_",
    ]

    init(autoplayPolicyStore: SumiAutoplayPolicyStoreAdapter? = nil) {
        self.autoplayPolicyStore = autoplayPolicyStore
    }

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
        autoplayPolicy: SumiAutoplayPolicy? = nil,
        userScriptsProvider: SumiNormalTabUserScripts? = nil,
        contentBlockingService: SumiContentBlockingService? = nil
    ) -> WKWebViewConfiguration {
        let config = makeBaseWebViewConfiguration()
        config.websiteDataStore = profile.dataStore
        config.userContentController = SumiNormalTabUserContentControllerFactory
            .makeController(
                scriptsProvider: userScriptsProvider,
                contentBlockingService: contentBlockingService,
                profileId: profile.id
            )
        applyMediaSessionPolicy(to: config, profile: profile)
        applyAutoplayPolicy(
            autoplayPolicy ?? resolvedAutoplayPolicy(for: url, profile: profile),
            to: config
        )
        return config
    }

    // MARK: - Auxiliary Surface Configuration

    /// Auxiliary WebViews are intentionally separate from primary normal tabs:
    /// popup WebViews come from WebKit, Peek/MiniWindow/Favicon use lightweight
    /// wrappers, and extension option pages may start from WebKit extension
    /// context config.
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
            ?? WKWebsiteDataStore.nonPersistent()
        config.userContentController = makeAuxiliaryUserContentController(
            additionalUserScripts: additionalUserScripts
        )
        config.defaultWebpagePreferences.allowsContentJavaScript =
            surface.allowsJavaScript
        config.preferences.javaScriptCanOpenWindowsAutomatically =
            surface.javaScriptCanOpenWindowsAutomatically

        if surface == .extensionOptions, let source {
            config.webExtensionController = source.webExtensionController
        }

        applyMediaSessionPolicy(to: config, profile: profile)
        return config
    }

    private func makeAuxiliaryUserContentController(
        additionalUserScripts: [WKUserScript]
    ) -> WKUserContentController {
        let controller = WKUserContentController()
        for userScript in filteredAuxiliaryUserScripts(additionalUserScripts) {
            controller.addUserScript(userScript)
        }
        return controller
    }

    private func filteredAuxiliaryUserScripts(
        _ userScripts: [WKUserScript]
    ) -> [WKUserScript] {
        userScripts.filter { userScript in
            Self.auxiliaryFilteredUserScriptMarkers.contains { marker in
                userScript.source.contains(marker)
            } == false
        }
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

    @MainActor
    func applyAutoplayPolicy(
        _ policy: SumiAutoplayPolicy,
        to configuration: WKWebViewConfiguration
    ) {
        configuration.mediaTypesRequiringUserActionForPlayback =
            policy.mediaTypesRequiringUserActionForPlayback
    }

    @MainActor
    func resolvedAutoplayPolicy(
        for url: URL?,
        profile: Profile
    ) -> SumiAutoplayPolicy {
        (autoplayPolicyStore ?? SumiAutoplayPolicyStoreAdapter.shared)
            .effectivePolicy(for: url, profile: profile)
    }
}
