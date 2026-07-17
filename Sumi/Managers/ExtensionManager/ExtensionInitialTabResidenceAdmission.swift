import Foundation
import SumiWebRuntime

@available(macOS 15.5, *)
@MainActor
struct ExtensionInitialTabResidence {
    let profile: Profile
    let profileID: UUID
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionInitialTabResidenceAdmission {
    private let browserProfiles: ExtensionBrowserProfileQuery
    private let tabProfiles: any ExtensionTabProfileResolving
    private let windowProfileID: @MainActor (BrowserWindowState) -> UUID?
    private let webViews: ExtensionExactTabWebViewQuery
    private let residences: BrowserTabResidenceAuthority

    init(
        browserProfiles: ExtensionBrowserProfileQuery,
        tabProfiles: any ExtensionTabProfileResolving,
        windowProfileID: @escaping @MainActor (BrowserWindowState) -> UUID?,
        webViews: ExtensionExactTabWebViewQuery,
        residences: BrowserTabResidenceAuthority
    ) {
        self.browserProfiles = browserProfiles
        self.tabProfiles = tabProfiles
        self.windowProfileID = windowProfileID
        self.webViews = webViews
        self.residences = residences
    }

    func admit(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView
    ) -> ExtensionInitialTabResidence? {
        guard window.isIncognito == false,
              tab.isEphemeral == false,
              let profileID = windowProfileID(window),
              tabProfiles.profileID(for: tab) == profileID,
              let profile = browserProfiles.anyProfile(profileID),
              webView.configuration.websiteDataStore === profile.dataStore,
              webViews.liveWebView(for: tab) === webView,
              window.currentTabId == tab.id,
              webView.owningTab === tab,
              residences.containsExact(tab, in: window),
              case .window(let owner) = tab.webViewSession.residence(of: webView),
              owner == TrackedWebViewOwner(tabID: tab.id, windowID: window.id)
        else { return nil }
        return ExtensionInitialTabResidence(profile: profile, profileID: profileID)
    }
}
