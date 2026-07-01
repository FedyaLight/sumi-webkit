import Foundation
import WebKit

@MainActor
struct TabWebViewConfigurationContext {
    let browserConfiguration: BrowserConfiguration
    let extensionNormalTabUserScripts: () -> [SumiUserScript]
    let userscriptsNormalTabUserScripts: (URL, UUID, UUID?, Bool) -> [SumiUserScript]
    let boostsNormalTabUserScripts: (URL, UUID?, Bool) -> [SumiUserScript]
    let protectionDecision: (URL, UUID) -> SumiProtectionNormalTabDecision?
    let protectionDesiredAttachmentState: (URL?) -> SumiProtectionAttachmentState
    let safariContentBlockerAttachmentState: (URL) -> SumiSafariContentBlockerAttachmentState?
    let safariBlockerDesiredAttachmentState: (URL?) -> SumiSafariContentBlockerAttachmentState
    let enabledSafariContentBlockingServices: (URL, UUID) -> [SumiContentBlockingService]
    let prepareWebViewConfigForExtensionRuntime: (WKWebViewConfiguration, UUID?, String) -> Void

    static let empty = TabWebViewConfigurationContext(
        browserConfiguration: .shared,
        extensionNormalTabUserScripts: { [] },
        userscriptsNormalTabUserScripts: { _, _, _, _ in [] },
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
        coreUserScripts: [SumiUserScript],
        tabId: UUID,
        profileIdProvider: () -> UUID?,
        context: TabWebViewConfigurationContext,
        isEphemeral: Bool
    ) -> SumiNormalTabUserScripts {
        SumiNormalTabUserScripts(
            managedUserScripts: normalTabManagedUserScripts(
                for: targetURL,
                coreUserScripts: coreUserScripts,
                tabId: tabId,
                profileIdProvider: profileIdProvider,
                context: context,
                isEphemeral: isEphemeral
            )
        )
    }

    func normalTabManagedUserScripts(
        for targetURL: URL?,
        coreUserScripts: [SumiUserScript],
        tabId: UUID,
        profileIdProvider: () -> UUID?,
        context: TabWebViewConfigurationContext,
        isEphemeral: Bool
    ) -> [SumiUserScript] {
        var scripts = coreUserScripts
        scripts.append(contentsOf: context.extensionNormalTabUserScripts())

        if let targetURL {
            scripts.append(
                contentsOf: context.userscriptsNormalTabUserScripts(
                    targetURL,
                    tabId,
                    profileIdProvider(),
                    isEphemeral
                )
            )

            scripts.append(
                contentsOf: context.boostsNormalTabUserScripts(
                    targetURL,
                    profileIdProvider(),
                    isEphemeral
                )
            )
        }

        return scripts
    }

    func normalTabWebViewConfiguration(
        for url: URL,
        profile: Profile,
        userScriptsProvider: SumiNormalTabUserScripts,
        context: TabWebViewConfigurationContext,
        reloadPolicyStateOwner: TabReloadPolicyStateOwner
    ) -> WKWebViewConfiguration {
        let protectionDecision = context.protectionDecision(url, profile.id)
        if let protectionDecision {
            reloadPolicyStateOwner.noteProtectionAttachmentApplied(protectionDecision.attachmentState)
        }

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
        if let safariContentBlockerAttachmentState {
            reloadPolicyStateOwner.noteSafariContentBlockerAttachmentApplied(
                safariContentBlockerAttachmentState
            )
        }

        let autoplayPolicy = context.browserConfiguration.resolvedAutoplayPolicy(
            for: url,
            profile: profile
        )

        return context.browserConfiguration.normalTabWebViewConfiguration(
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
        reloadPolicyStateOwner: TabReloadPolicyStateOwner
    ) -> Bool {
        guard webView.configuration.sumiIsNormalTabWebViewConfiguration else {
            return false
        }

        let desiredProtectionState = context.protectionDesiredAttachmentState(webView.url ?? fallbackURL)
        if let appliedProtectionState = reloadPolicyStateOwner.protectionAppliedAttachmentState {
            guard appliedProtectionState == desiredProtectionState else {
                return false
            }
        } else if desiredProtectionState.isEnabled {
            return false
        }

        let desiredSafariContentBlockerState = context
            .safariBlockerDesiredAttachmentState(webView.url ?? fallbackURL)
        if let appliedSafariContentBlockerState =
            reloadPolicyStateOwner.safariContentBlockerAppliedAttachmentState {
            guard appliedSafariContentBlockerState
                .hasSameEffectiveWebViewAttachment(as: desiredSafariContentBlockerState)
            else {
                return false
            }
            if appliedSafariContentBlockerState != desiredSafariContentBlockerState {
                reloadPolicyStateOwner.noteSafariContentBlockerAttachmentApplied(
                    desiredSafariContentBlockerState
                )
            }
        } else if desiredSafariContentBlockerState.isEnabled {
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
