import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupSourceReceipt {
    struct ResolvedSource {
        let windowState: BrowserWindowState
        let window: NSWindow
        let tab: Tab
    }

    let extensionID: String
    let profileID: UUID
    let windowID: UUID
    let tabID: UUID

    private weak var windowState: BrowserWindowState?
    private weak var window: NSWindow?
    private weak var tab: Tab?
    private weak var popupWebView: WKWebView?
    private let profile: Profile
    private var isValid = true

    private init(
        extensionID: String,
        profileID: UUID,
        windowID: UUID,
        tabID: UUID,
        windowState: BrowserWindowState,
        window: NSWindow,
        tab: Tab,
        profile: Profile,
        popupWebView: WKWebView
    ) {
        self.extensionID = extensionID
        self.profileID = profileID
        self.windowID = windowID
        self.tabID = tabID
        self.windowState = windowState
        self.window = window
        self.tab = tab
        self.profile = profile
        self.popupWebView = popupWebView
    }

    static func capture(
        extensionID: String,
        profileID: UUID,
        anchor: ExtensionActionPopupAnchor,
        popupWebView: WKWebView,
        manager: ExtensionManager
    ) -> ExtensionActionPopupSourceReceipt? {
        guard anchor.extensionID == extensionID,
              anchor.profileID == profileID,
              let tabID = anchor.tabID,
              let query = manager.extensionWindowQuery,
              let windowState = query.extensionWindowState(for: anchor.windowID),
              manager.windowMatchesProfile(windowState, profileId: profileID),
              let window = query.appKitWindow(for: windowState),
              let tab = query.extensionTab(withID: tabID, in: windowState),
              manager.resolvedProfileId(for: tab) == profileID,
              let profile = manager.runtime.profile(profileID)
                ?? manager.runtime.ephemeralProfile(profileID),
              tab.resolveProfile() === profile,
              popupWebView.configuration.websiteDataStore === profile.dataStore,
              controllerMatchesProfile(
                popupWebView.configuration.webExtensionController,
                profileID: profileID,
                manager: manager
              )
        else {
            return nil
        }

        return ExtensionActionPopupSourceReceipt(
            extensionID: extensionID,
            profileID: profileID,
            windowID: anchor.windowID,
            tabID: tabID,
            windowState: windowState,
            window: window,
            tab: tab,
            profile: profile,
            popupWebView: popupWebView
        )
    }

    func resolve(
        popupWebView: WKWebView,
        childConfiguration: WKWebViewConfiguration,
        manager: ExtensionManager
    ) -> ResolvedSource? {
        guard isValid,
              self.popupWebView === popupWebView,
              popupWebView.configuration.websiteDataStore === profile.dataStore,
              childConfiguration.websiteDataStore === profile.dataStore,
              Self.controllerMatchesProfile(
                popupWebView.configuration.webExtensionController,
                profileID: profileID,
                manager: manager
              ),
              Self.controllerMatchesProfile(
                childConfiguration.webExtensionController,
                profileID: profileID,
                manager: manager
              ),
              Self.controllersMatchWhenPresent(
                popupWebView.configuration.webExtensionController,
                childConfiguration.webExtensionController
              ),
              let expectedWindowState = windowState,
              let expectedWindow = window,
              let expectedTab = tab,
              let query = manager.extensionWindowQuery,
              query.extensionWindowState(for: windowID) === expectedWindowState,
              query.appKitWindow(for: expectedWindowState) === expectedWindow,
              query.extensionTab(withID: tabID, in: expectedWindowState) === expectedTab,
              manager.windowMatchesProfile(expectedWindowState, profileId: profileID),
              manager.resolvedProfileId(for: expectedTab) == profileID,
              expectedTab.resolveProfile() === profile,
              (manager.runtime.profile(profileID)
                ?? manager.runtime.ephemeralProfile(profileID)) === profile
        else {
            return nil
        }

        return ResolvedSource(
            windowState: expectedWindowState,
            window: expectedWindow,
            tab: expectedTab
        )
    }

    func invalidate() {
        isValid = false
    }

    private static func controllerMatchesProfile(
        _ controller: WKWebExtensionController?,
        profileID: UUID,
        manager: ExtensionManager
    ) -> Bool {
        guard let controller else { return true }
        return manager.profileId(for: controller) == profileID
    }

    private static func controllersMatchWhenPresent(
        _ first: WKWebExtensionController?,
        _ second: WKWebExtensionController?
    ) -> Bool {
        guard let first, let second else { return true }
        return first === second
    }
}
