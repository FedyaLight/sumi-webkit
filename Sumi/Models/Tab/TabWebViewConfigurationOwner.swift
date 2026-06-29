import Foundation
import WebKit

@MainActor
final class TabWebViewConfigurationOwner {
    var webViewConfigurationOverride: WKWebViewConfiguration?
    var webExtensionContextOverride: WKWebExtensionContext?

    func normalTabUserScriptsProvider(
        for targetURL: URL?,
        coreUserScripts: [SumiUserScript],
        tabId: UUID,
        profileIdProvider: () -> UUID?,
        browserManager: BrowserManager?,
        isEphemeral: Bool
    ) -> SumiNormalTabUserScripts {
        SumiNormalTabUserScripts(
            managedUserScripts: normalTabManagedUserScripts(
                for: targetURL,
                coreUserScripts: coreUserScripts,
                tabId: tabId,
                profileIdProvider: profileIdProvider,
                browserManager: browserManager,
                isEphemeral: isEphemeral
            )
        )
    }

    func normalTabManagedUserScripts(
        for targetURL: URL?,
        coreUserScripts: [SumiUserScript],
        tabId: UUID,
        profileIdProvider: () -> UUID?,
        browserManager: BrowserManager?,
        isEphemeral: Bool
    ) -> [SumiUserScript] {
        var scripts = coreUserScripts
        scripts.append(contentsOf: browserManager?.extensionsModule.normalTabUserScripts() ?? [])

        if let targetURL {
            scripts.append(
                contentsOf: browserManager?.userscriptsModule.normalTabUserScripts(
                    for: targetURL,
                    webViewId: tabId,
                    profileId: profileIdProvider(),
                    isEphemeral: isEphemeral
                ) ?? []
            )

            scripts.append(
                contentsOf: browserManager?.boostsModule.normalTabUserScripts(
                    for: targetURL,
                    profileId: profileIdProvider(),
                    isEphemeral: isEphemeral
                ) ?? []
            )
        }

        return scripts
    }

    func normalTabWebViewConfiguration(
        for url: URL,
        profile: Profile,
        userScriptsProvider: SumiNormalTabUserScripts,
        browserManager: BrowserManager?,
        reloadPolicyStateOwner: TabReloadPolicyStateOwner
    ) -> WKWebViewConfiguration {
        let protectionDecision = browserManager?.protectionCoordinator
            .normalTabDecision(for: url, profileId: profile.id)
        if let protectionDecision {
            reloadPolicyStateOwner.noteProtectionAttachmentApplied(protectionDecision.attachmentState)
        }

        let safariContentBlockerAttachmentState = browserManager?
            .extensionsModule
            .safariContentBlockerAttachmentState(for: url)
        let additionalContentBlockingServices: [SumiContentBlockingService]
        if safariContentBlockerAttachmentState?.isEnabled == true {
            additionalContentBlockingServices = browserManager?
                .extensionsModule
                .enabledSafariContentBlockingServices(
                    for: url,
                    profileId: profile.id
                ) ?? []
        } else {
            additionalContentBlockingServices = []
        }
        if let safariContentBlockerAttachmentState {
            reloadPolicyStateOwner.noteSafariContentBlockerAttachmentApplied(
                safariContentBlockerAttachmentState
            )
        }

        let autoplayPolicy = BrowserConfiguration.shared.resolvedAutoplayPolicy(
            for: url,
            profile: profile
        )

        return BrowserConfiguration.shared.normalTabWebViewConfiguration(
            for: profile,
            url: url,
            autoplayPolicy: autoplayPolicy,
            userScriptsProvider: userScriptsProvider,
            contentBlockingService: protectionDecision?.contentBlockingService,
            additionalContentBlockingServices: additionalContentBlockingServices
        )
    }

    func auxiliaryOverrideConfiguration(
        for profile: Profile,
        browserManager: BrowserManager?
    ) -> WKWebViewConfiguration? {
        if let configuration = webExtensionContextWebViewConfiguration(
            profile: profile,
            browserManager: browserManager
        ) {
            return configuration
        }

        return webViewConfigurationOverride.map { override in
            BrowserConfiguration.shared.auxiliaryWebViewConfiguration(
                from: override,
                for: profile,
                surface: .extensionOptions,
                additionalUserScripts: override.userContentController.userScripts
            )
        }
    }

    func applyWebViewConfigurationOverride(
        _ configuration: WKWebViewConfiguration,
        profileId: UUID?,
        browserManager: BrowserManager?
    ) {
        let isolatedConfiguration = BrowserConfiguration.shared.auxiliaryWebViewConfiguration(
            from: configuration,
            surface: .extensionOptions,
            additionalUserScripts: configuration.userContentController.userScripts
        )
        browserManager?.extensionsModule.prepareWebViewConfigurationForExtensionRuntime(
            isolatedConfiguration,
            profileId: profileId,
            reason: "Tab.applyWebViewConfigurationOverride"
        )
        webViewConfigurationOverride = isolatedConfiguration
    }

    func canReuseAsNormalTabWebView(
        _ webView: WKWebView,
        fallbackURL: URL,
        tabId: UUID,
        profile: Profile?,
        browserManager: BrowserManager?,
        reloadPolicyStateOwner: TabReloadPolicyStateOwner
    ) -> Bool {
        guard webView.configuration.sumiIsNormalTabWebViewConfiguration else {
            return false
        }

        let desiredProtectionState = reloadPolicyStateOwner.protectionDesiredAttachmentState(
            for: webView.url ?? fallbackURL,
            browserManager: browserManager
        )
        if let appliedProtectionState = reloadPolicyStateOwner.protectionAppliedAttachmentState {
            guard appliedProtectionState == desiredProtectionState else {
                return false
            }
        } else if desiredProtectionState.isEnabled {
            return false
        }

        guard let profile,
              webView.configuration.websiteDataStore === profile.dataStore
        else {
            return false
        }
        guard let provider = webView.configuration.userContentController.sumiNormalTabUserScriptsProvider else {
            return false
        }
        let suspensionContext = "sumiTabSuspension_\(tabId.uuidString)"
        return provider.userScripts.contains { script in
            script.source.contains(suspensionContext)
        }
    }

    func shouldDelayInitialNormalTabRuntimeRegistration(
        isPopupHost: Bool,
        hasExistingWebView: Bool,
        didCreateAuxiliaryOverrideWebView: Bool,
        url: URL
    ) -> Bool {
        !isPopupHost
            && !hasExistingWebView
            && !didCreateAuxiliaryOverrideWebView
            && Self.isInitialDocumentExtensionWarmupURL(url)
    }

    static func isInitialDocumentExtensionWarmupURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    private func webExtensionContextWebViewConfiguration(
        profile: Profile,
        browserManager: BrowserManager?
    ) -> WKWebViewConfiguration? {
        guard let context = webExtensionContextOverride,
              let configuration = context.webViewConfiguration
        else { return nil }

        browserManager?.extensionsModule.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "Tab.webExtensionContextWebViewConfiguration"
        )
        return configuration
    }
}
