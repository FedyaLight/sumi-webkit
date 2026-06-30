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
    let safariContentBlockerDesiredAttachmentState: (URL?) -> SumiSafariContentBlockerAttachmentState
    let enabledSafariContentBlockingServices: (URL, UUID) -> [SumiContentBlockingService]
    let prepareWebViewConfigurationForExtensionRuntime: (WKWebViewConfiguration, UUID?, String) -> Void

    static let empty = TabWebViewConfigurationContext(
        browserConfiguration: .shared,
        extensionNormalTabUserScripts: { [] },
        userscriptsNormalTabUserScripts: { _, _, _, _ in [] },
        boostsNormalTabUserScripts: { _, _, _ in [] },
        protectionDecision: { _, _ in nil },
        protectionDesiredAttachmentState: { _ in .disabled(siteHost: nil) },
        safariContentBlockerAttachmentState: { _ in nil },
        safariContentBlockerDesiredAttachmentState: { _ in .disabled(siteHost: nil) },
        enabledSafariContentBlockingServices: { _, _ in [] },
        prepareWebViewConfigurationForExtensionRuntime: { _, _, _ in }
    )

    static func live(browserManager: BrowserManager?) -> Self {
        guard let browserManager else { return .empty }
        return TabWebViewConfigurationContext(
            browserConfiguration: .shared,
            extensionNormalTabUserScripts: {
                browserManager.extensionsModule.normalTabUserScripts()
            },
            userscriptsNormalTabUserScripts: { url, tabId, profileId, isEphemeral in
                browserManager.userscriptsModule.normalTabUserScripts(
                    for: url,
                    webViewId: tabId,
                    profileId: profileId,
                    isEphemeral: isEphemeral
                )
            },
            boostsNormalTabUserScripts: { url, profileId, isEphemeral in
                browserManager.boostsModule.normalTabUserScripts(
                    for: url,
                    profileId: profileId,
                    isEphemeral: isEphemeral
                )
            },
            protectionDecision: { url, profileId in
                browserManager.protectionCoordinator.normalTabDecision(
                    for: url,
                    profileId: profileId
                )
            },
            protectionDesiredAttachmentState: { url in
                browserManager.protectionCoordinator.desiredAttachmentState(for: url)
            },
            safariContentBlockerAttachmentState: { url in
                browserManager.extensionsModule.safariContentBlockerAttachmentState(for: url)
            },
            safariContentBlockerDesiredAttachmentState: { url in
                browserManager.extensionsModule.safariContentBlockerAttachmentState(for: url)
            },
            enabledSafariContentBlockingServices: { url, profileId in
                browserManager.extensionsModule.enabledSafariContentBlockingServices(
                    for: url,
                    profileId: profileId
                )
            },
            prepareWebViewConfigurationForExtensionRuntime: { configuration, profileId, reason in
                browserManager.extensionsModule.prepareWebViewConfigurationForExtensionRuntime(
                    configuration,
                    profileId: profileId,
                    reason: reason
                )
            }
        )
    }
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
        context.prepareWebViewConfigurationForExtensionRuntime(
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
            .safariContentBlockerDesiredAttachmentState(webView.url ?? fallbackURL)
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

        context.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profile.id,
            "Tab.webExtensionContextWebViewConfiguration"
        )
        return configuration
    }
}
