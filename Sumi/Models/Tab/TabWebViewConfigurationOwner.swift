import Foundation
import SumiDomain
import WebKit

@MainActor
struct TabWebViewConfigurationContext {
    let browserConfiguration: BrowserConfiguration
    let extensionNormalTabUserScripts: () -> [SumiPageScript]
    let boostsNormalTabUserScripts: (URL, UUID?, Bool) -> [SumiPageScript]
    let protectionDecision: (URL, UUID) -> SumiProtectionNormalTabDecision?
    let protectionDesiredAttachmentState: (URL?) -> SumiProtectionAttachmentState
    let safariContentBlockerAttachmentState: (URL) -> SumiSafariContentBlockerAttachmentState?
    let safariBlockerDesiredAttachmentState: (URL?) -> SumiSafariContentBlockerAttachmentState
    let enabledSafariContentBlockingServices: (URL, UUID) -> [SumiContentBlockingService]
    let prepareWebViewConfigForExtensionRuntime: (WKWebViewConfiguration, UUID?, String) -> Void

    static let empty = TabWebViewConfigurationContext(
        browserConfiguration: .shared,
        extensionNormalTabUserScripts: { [] },
        boostsNormalTabUserScripts: { _, _, _ in [] },
        protectionDecision: { _, _ in nil },
        protectionDesiredAttachmentState: { _ in .disabled(siteHost: nil) },
        safariContentBlockerAttachmentState: { _ in nil },
        safariBlockerDesiredAttachmentState: { _ in .disabled(siteHost: nil) },
        enabledSafariContentBlockingServices: { _, _ in [] },
        prepareWebViewConfigForExtensionRuntime: { _, _, _ in /* No-op. */ }
    )
}

@MainActor
final class TabWebViewConfigurationOwner {
    var webViewConfigurationOverride: WKWebViewConfiguration?
    var webExtensionContextOverride: WKWebExtensionContext?

    func normalTabUserScriptsProvider(
        for targetURL: URL?,
        coreUserScripts: [SumiPageScript],
        profileIdProvider: () -> UUID?,
        context: TabWebViewConfigurationContext,
        isEphemeral: Bool
    ) -> SumiNormalTabUserScripts {
        SumiNormalTabUserScripts(
            staticManagedUserScripts: normalTabStaticManagedUserScripts(
                coreUserScripts: coreUserScripts,
                context: context
            ),
            navigationUserScripts: normalTabNavigationUserScripts(
                for: targetURL,
                profileIdProvider: profileIdProvider,
                context: context,
                isEphemeral: isEphemeral
            )
        )
    }

    func normalTabManagedUserScripts(
        for targetURL: URL?,
        coreUserScripts: [SumiPageScript],
        profileIdProvider: () -> UUID?,
        context: TabWebViewConfigurationContext,
        isEphemeral: Bool
    ) -> [SumiPageScript] {
        normalTabStaticManagedUserScripts(
            coreUserScripts: coreUserScripts,
            context: context
        ) + normalTabNavigationUserScripts(
            for: targetURL,
            profileIdProvider: profileIdProvider,
            context: context,
            isEphemeral: isEphemeral
        )
    }

    func normalTabStaticManagedUserScripts(
        coreUserScripts: [SumiPageScript],
        context: TabWebViewConfigurationContext
    ) -> [SumiPageScript] {
        coreUserScripts + context.extensionNormalTabUserScripts()
    }

    func normalTabNavigationUserScripts(
        for targetURL: URL?,
        profileIdProvider: () -> UUID?,
        context: TabWebViewConfigurationContext,
        isEphemeral: Bool
    ) -> [SumiPageScript] {
        guard let targetURL else { return [] }
        return context.boostsNormalTabUserScripts(
            targetURL,
            profileIdProvider(),
            isEphemeral
        )
    }

    func normalTabWebViewConfiguration(
        for url: URL,
        profile: Profile,
        userScriptsProvider: SumiNormalTabUserScripts,
        context: TabWebViewConfigurationContext
    ) -> PreparedNormalTabWebViewConfiguration {
        let protectionDecision = context.protectionDecision(url, profile.id)
        let safariContentBlockerAttachmentState = context.safariContentBlockerAttachmentState(url)
        let additionalContentBlockingServices: [SumiContentBlockingService]
        if safariContentBlockerAttachmentState?.isEnabled == true {
            additionalContentBlockingServices = context.enabledSafariContentBlockingServices(
                url,
                profile.id
            )
        } else {
            additionalContentBlockingServices = []
        }

        let autoplayPolicy = context.browserConfiguration.resolvedAutoplayPolicy(
            for: url,
            profile: profile
        )

        let configuration = context.browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: url,
            autoplayPolicy: autoplayPolicy,
            userScriptsProvider: userScriptsProvider,
            contentBlockingService: protectionDecision?.contentBlockingService,
            additionalContentBlockingServices: additionalContentBlockingServices
        )
        let policyState = TabConfigurationPolicyState(
            profileID: profile.id,
            websiteDataStoreIdentity: ObjectIdentifier(
                configuration.websiteDataStore
            ),
            protectionAttachment: protectionDecision?.attachmentState,
            safariContentBlockerAttachment:
                safariContentBlockerAttachmentState,
            autoplayState: autoplayPolicy.runtimeState
        )
        return PreparedNormalTabWebViewConfiguration(
            configuration: configuration,
            policyState: policyState
        )
    }

    func auxiliaryOverrideConfiguration(
        for profile: Profile,
        context: TabWebViewConfigurationContext
    ) -> WKWebViewConfiguration? {
        if let configuration = webExtensionContextWebViewConfiguration(
            profile: profile,
            context: context
        ) {
            return configuration
        }

        return webViewConfigurationOverride.map { override in
            context.browserConfiguration.auxiliaryWebViewConfiguration(
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
        context: TabWebViewConfigurationContext
    ) {
        let isolatedConfiguration = context.browserConfiguration.auxiliaryWebViewConfiguration(
            from: configuration,
            surface: .extensionOptions,
            additionalUserScripts: configuration.userContentController.userScripts
        )
        context.prepareWebViewConfigForExtensionRuntime(
            isolatedConfiguration,
            profileId,
            "Tab.applyWebViewConfigurationOverride"
        )
        webViewConfigurationOverride = isolatedConfiguration
    }

    func canReuseAsNormalTabWebView(
        _ webView: WKWebView,
        fallbackURL: URL,
        tabId: UUID,
        profile: Profile?,
        context: TabWebViewConfigurationContext,
        policyLedger: TabConfigurationPolicyLedger
    ) -> Bool {
        guard webView.configuration.sumiIsNormalTabWebViewConfiguration else {
            return false
        }

        let desiredProtectionState = context.protectionDesiredAttachmentState(webView.url ?? fallbackURL)
        if let appliedProtectionState = policyLedger.protectionAttachment {
            guard appliedProtectionState.hasSameEffectiveWebViewAttachment(
                as: desiredProtectionState
            ) else {
                return false
            }
        } else if desiredProtectionState.isEnabled {
            return false
        }

        let desiredSafariContentBlockerState = context
            .safariBlockerDesiredAttachmentState(webView.url ?? fallbackURL)
        if let appliedSafariContentBlockerState =
            policyLedger.safariContentBlockerAttachment {
            guard appliedSafariContentBlockerState
                .hasSameEffectiveWebViewAttachment(as: desiredSafariContentBlockerState)
            else {
                return false
            }
        } else if desiredSafariContentBlockerState.isEnabled {
            return false
        }

        guard let profile,
              webView.configuration.websiteDataStore === profile.dataStore
        else {
            return false
        }
        let physicalAutoplayState = SumiRuntimePermissionController
            .autoplayState(
                from: webView.configuration
                    .mediaTypesRequiringUserActionForPlayback
            )
        let desiredAutoplayState = context.browserConfiguration
            .resolvedAutoplayPolicy(
                for: webView.url ?? fallbackURL,
                profile: profile
            )
            .runtimeState
        guard physicalAutoplayState == desiredAutoplayState else {
            return false
        }
        guard let provider = webView.configuration.userContentController.sumiNormalTabUserScriptsProvider else {
            return false
        }
        return provider.userScripts.contains { script in
            (script as? SumiTabSuspensionUserScript)?.tabID == tabId
        }
    }

    private func webExtensionContextWebViewConfiguration(
        profile: Profile,
        context: TabWebViewConfigurationContext
    ) -> WKWebViewConfiguration? {
        guard let webExtensionContext = webExtensionContextOverride,
              let configuration = webExtensionContext.webViewConfiguration
        else { return nil }

        context.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profile.id,
            "Tab.webExtensionContextWebViewConfiguration"
        )
        return configuration
    }
}
