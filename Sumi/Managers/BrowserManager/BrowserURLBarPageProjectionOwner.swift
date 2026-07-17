import Foundation
import SumiDomain
import WebKit

@MainActor
final class BrowserURLBarPageProjectionOwner {
    private let profileManager: ProfileManager
    private let currentProfile: BrowserCurrentProfileAuthority
    private let webViews: BrowserWebViewRoutingService
    private let extensionActions: BrowserURLBarExtensionActionContextOwner
    private let siteControls: BrowserSiteControlsContextOwner

    init(
        profileManager: ProfileManager,
        currentProfile: BrowserCurrentProfileAuthority,
        webViews: BrowserWebViewRoutingService,
        extensionActions: BrowserURLBarExtensionActionContextOwner,
        siteControls: BrowserSiteControlsContextOwner
    ) {
        self.profileManager = profileManager
        self.currentProfile = currentProfile
        self.webViews = webViews
        self.extensionActions = extensionActions
        self.siteControls = siteControls
    }

    var profiles: [Profile] {
        profileManager.profiles
    }

    var selectedProfile: Profile? {
        currentProfile.currentProfile
    }

    var extensionActionContext: URLBarExtensionActionContext {
        extensionActions.context
    }

    func webView(for tab: Tab, in windowState: BrowserWindowState) -> WKWebView? {
        webViews.windowOwnedWebView(for: tab, in: windowState.id)
    }

    func siteControlsSnapshot(
        url: URL?,
        profile: Profile?,
        protectionReloadRequired: Bool,
        contentBlockerReloadRequired: Bool
    ) -> SiteControlsSnapshot {
        siteControls.snapshot(
            url: url,
            profile: profile,
            protectionReloadRequired: protectionReloadRequired,
            contentBlockerReloadRequired: contentBlockerReloadRequired
        )
    }
}
