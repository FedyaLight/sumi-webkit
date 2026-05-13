//
//  BrowserConfig.swift
//  Sumi
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import AppKit
import ObjectiveC.runtime
import SwiftUI
import WebKit

enum BrowserConfigurationAuxiliarySurface: String, CaseIterable {
    case faviconDownload
    case glance
    case miniWindow
    case extensionOptions

    var sumiWebContentProcessDisplayName: String {
        switch self {
        case .faviconDownload:
            return "Sumi Web Content (Favicon)"
        case .glance:
            return "Sumi Web Content (Peek)"
        case .miniWindow:
            return "Sumi Web Content (Mini Window)"
        case .extensionOptions:
            return "Sumi Web Content (Extension Options)"
        }
    }

    var allowsJavaScript: Bool {
        switch self {
        case .faviconDownload:
            return false
        case .glance, .miniWindow, .extensionOptions:
            return true
        }
    }

    var javaScriptCanOpenWindowsAutomatically: Bool {
        switch self {
        case .faviconDownload:
            return false
        case .glance, .miniWindow, .extensionOptions:
            return true
        }
    }
}

@MainActor
class BrowserConfiguration {
    static let shared = BrowserConfiguration()

    let webKitProcessPoolContext = SumiWebKitProcessPoolContext()
    private let autoplayPolicyStore: SumiAutoplayPolicyStoreAdapter?
    private let visitedLinkStoreProvider: SharedVisitedLinkStoreProvider
    private static let auxiliaryFilteredUserScriptMarkers = [
        "__sumiDDGFaviconTransportInstalled",
        "__sumiTabSuspension",
        SumiTransientChromeInteractionShieldUserScript.sourceMarker,
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

    init(
        autoplayPolicyStore: SumiAutoplayPolicyStoreAdapter? = nil,
        visitedLinkStoreProvider: SharedVisitedLinkStoreProvider? = nil
    ) {
        self.autoplayPolicyStore = autoplayPolicyStore
        self.visitedLinkStoreProvider = visitedLinkStoreProvider ?? .shared
    }

    private func makeBaseWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        webKitProcessPoolContext.apply(to: config)
        config.applicationNameForUserAgent =
            SumiUserAgent.safariCompatibleApplicationNameForUserAgent
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

        // DDG parity: WebKit owns normal media, fullscreen, and system MediaSession behavior.
        config.preferences.isElementFullscreenEnabled = true
        if !NSApp.sumiIsSandboxed {
            SumiSetAllowsPictureInPictureMediaPlayback(config.preferences, true)
        }

        // Enable background media playback
        config.allowsAirPlayForMediaPlayback = true

        config.preferences.setValue(
            RuntimeDiagnostics.isDeveloperInspectionEnabled,
            forKey: "developerExtrasEnabled"
        )

        // Note: WebAuthn/Passkey support is enabled by default in WKWebView on macOS 13.3+
        // and requires only: entitlements, WKUIDelegate methods, and Info.plist descriptions

        return config
    }

    lazy var webViewConfiguration: WKWebViewConfiguration = {
        let config = makeBaseWebViewConfiguration()
        WebContentProcessDisplayNameProvider.apply(
            WebContentProcessDisplayNameProvider.auxiliaryTemplate,
            to: config
        )
        return config
    }()

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
        config.sumiIsNormalTabWebViewConfiguration = true
        config.websiteDataStore = profile.dataStore
        visitedLinkStoreProvider.applyStore(to: config, for: profile)
        config.userContentController = SumiNormalTabUserContentControllerFactory
            .makeController(
                scriptsProvider: userScriptsProvider,
                contentBlockingService: contentBlockingService,
                profileId: profile.id
            )
        applyAutoplayPolicy(
            autoplayPolicy ?? resolvedAutoplayPolicy(for: url, profile: profile),
            to: config
        )
        WebContentProcessDisplayNameProvider.apply(
            WebContentProcessDisplayNameProvider.normalTab,
            to: config
        )
        return config
    }

    // MARK: - Auxiliary Surface Configuration

    /// Auxiliary WebViews are intentionally separate from primary normal tabs:
    /// popup WebViews come from WebKit, Glance/MiniWindow/Favicon use lightweight
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
        if let profile {
            visitedLinkStoreProvider.applyStore(to: config, for: profile)
        } else {
            visitedLinkStoreProvider.applyStoreFromSourceIfAvailable(
                to: config,
                source: source
            )
        }
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

        WebContentProcessDisplayNameProvider.apply(
            surface.sumiWebContentProcessDisplayName,
            to: config
        )
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
    func applyAutoplayPolicy(
        _ policy: SumiAutoplayPolicy,
        to configuration: WKWebViewConfiguration
    ) {
        // Fallback only. Normal tabs enforce autoplay through per-navigation
        // WKWebpagePreferences in SumiAutoplayPolicyNavigationResponder.
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

final class SumiWebKitProcessPoolContext {
    private let processPool: NSObject

    init() {
        guard let processPoolClass = NSClassFromString("WKProcessPool") as? NSObject.Type else {
            preconditionFailure("WKProcessPool class is unavailable")
        }
        self.processPool = processPoolClass.init()
    }

    func apply(to configuration: WKWebViewConfiguration) {
        configuration.setValue(processPool, forKey: "processPool")
    }

    var opaquePointer: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(processPool).toOpaque())
    }
}

private enum BrowserConfigurationAssociatedKeys {
    private static let isNormalTabWebViewConfigurationStorage =
        StaticString("Sumi.BrowserConfiguration.isNormalTabWebViewConfiguration")

    static var isNormalTabWebViewConfiguration: UnsafeRawPointer {
        UnsafeRawPointer(isNormalTabWebViewConfigurationStorage.utf8Start)
    }
}

extension WKWebViewConfiguration {
    var sumiIsNormalTabWebViewConfiguration: Bool {
        get {
            (objc_getAssociatedObject(
                self,
                BrowserConfigurationAssociatedKeys.isNormalTabWebViewConfiguration
            ) as? Bool) == true
        }
        set {
            objc_setAssociatedObject(
                self,
                BrowserConfigurationAssociatedKeys.isNormalTabWebViewConfiguration,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

private extension NSApplication {
    var sumiIsSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
