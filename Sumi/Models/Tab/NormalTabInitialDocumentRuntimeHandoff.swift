import Foundation
import WebKit

@MainActor
enum NormalTabInitialDocumentRuntimeHandoff {
    enum TabSetupRegistrationGuard: Sendable {
        case noExistingWebView
        case currentWebViewIdentity
    }

    static func perform(
        waitForInitialUserContent: @MainActor () async -> Void,
        warmInitialDocumentContexts: @MainActor () async -> Void,
        isStillValid: @MainActor () -> Bool,
        register: @MainActor () -> Void,
        load: @MainActor () -> Void
    ) async {
        await waitForInitialUserContent()
        guard isStillValid() else { return }
        await warmInitialDocumentContexts()
        guard isStillValid() else { return }
        register()
        load()
    }

    static func scheduleTabSetupInitialLoad(
        tab: Tab,
        webView: WKWebView?,
        targetURL: URL,
        profileId: UUID?,
        registrationReason: String,
        registrationGuard: TabSetupRegistrationGuard
    ) {
        let controller = webView?.configuration.userContentController
            .sumiNormalTabUserContentController

        Task { @MainActor [weak tab, weak webView] in
            await perform {
                await waitForInitialUserContentInstallationIfNeeded(controller)
            } warmInitialDocumentContexts: {
                await warmInitialDocumentContextsIfNeeded(
                    tab: tab,
                    profileId: profileId
                )
            } isStillValid: {
                guard let tab else { return false }
                switch registrationGuard {
                case .noExistingWebView:
                    return !tab.hasParkedWebView
                case .currentWebViewIdentity:
                    guard let webView else { return false }
                    return !tab.hasParkedWebView
                        && tab.currentWebViewIsIdentical(to: webView)
                }
            } register: {
                tab?.registerTabWithExtensionRuntimeIfNeeded(
                    reason: registrationReason
                )
            } load: {
                tab?.loadURL(targetURL)
            }
        }
    }

    @available(macOS 15.5, *)
    static func scheduleCloneInitialLoad(
        tab: Tab,
        webView: WKWebView,
        targetURL: URL,
        profileId: UUID?,
        registrationReason: String
    ) {
        let controller = webView.configuration.userContentController
            .sumiNormalTabUserContentController

        Task { @MainActor [weak tab, weak webView] in
            await perform {
                await waitForInitialUserContentInstallationIfNeeded(controller)
            } warmInitialDocumentContexts: {
                await warmInitialDocumentContextsIfNeeded(
                    tab: tab,
                    profileId: profileId
                )
            } isStillValid: {
                tab != nil
            } register: {
                tab?.registerTabWithExtensionRuntimeIfNeeded(
                    reason: registrationReason
                )
            } load: {
                guard let tab, let webView else { return }
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView
                ) { resolvedWebView in
                    guard !resolvedWebView.isLoading,
                          resolvedWebView.url == nil else {
                        return
                    }
                    resolvedWebView.load(URLRequest(url: targetURL))
                }
            }
        }
    }

    private static func waitForInitialUserContentInstallationIfNeeded(
        _ controller: SumiNormalTabUserContentControlling?
    ) async {
        if let controller,
           controller.hasInstalledInitialUserContent == false {
            await controller.waitForInitialUserContentInstallation()
        }
    }

    private static func warmInitialDocumentContextsIfNeeded(
        tab: Tab?,
        profileId: UUID?
    ) async {
        if let profileId, let tab {
            await tab.normalWebViewExtensionRuntime
                .ensureInitialExtensionContextsIfNeeded(profileId)
        }
    }
}
