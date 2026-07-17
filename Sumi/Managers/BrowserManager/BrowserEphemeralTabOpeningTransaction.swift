import Foundation
import SumiDomain
import WebKit

@MainActor
final class BrowserEphemeralTabOpeningTransaction {
    private let lifecycle: TabEphemeralLifecycleOwner
    private let settings: BrowserSettingsState
    private let activation: BrowserTabOpenActivation

    init(
        lifecycle: TabEphemeralLifecycleOwner,
        settings: BrowserSettingsState,
        activation: BrowserTabOpenActivation
    ) {
        self.lifecycle = lifecycle
        self.settings = settings
        self.activation = activation
    }

    func open(
        url: String,
        context: BrowserTabOpenContext,
        windowState: BrowserWindowState,
        profile: Profile
    ) -> Tab {
        let template = settings.settings?.resolvedSearchEngineTemplate
            ?? SearchProvider.google.queryTemplate
        let normalizedURL = normalizeURL(url, queryTemplate: template)
        let resolvedURL = URL(string: normalizedURL)
            ?? SumiSurface.emptyTabURL
        let previousTabID = windowState.currentTabId
        let tab = lifecycle.createEphemeralTab(
            url: resolvedURL,
            in: windowState,
            profile: profile
        )
        windowState.markWebKitChildWindowAdopted(by: tab.id)
        if case .background = context.activationPolicy {
            windowState.currentTabId = previousTabID
        }
        activation.apply(
            context.activationPolicy,
            to: tab,
            resolvedWindow: windowState
        )
        return tab
    }

    func createPopup(
        from sourceTab: Tab,
        windowState: BrowserWindowState,
        profile: Profile,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        activate: Bool
    ) -> Tab? {
        guard let blankURL = URL(string: "about:blank") else { return nil }
        let previousTabID = windowState.currentTabId
        let tab = lifecycle.createEphemeralTab(
            url: blankURL,
            in: windowState,
            profile: profile
        )
        windowState.markWebKitChildWindowAdopted(by: tab.id)
        tab.isPopupHost = true
        if let webViewConfigurationOverride {
            tab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
        }
        if !activate {
            windowState.currentTabId = previousTabID
        }
        return tab
    }
}
