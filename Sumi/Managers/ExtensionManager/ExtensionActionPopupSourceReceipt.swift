import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupSourceAdmission {
    private let callbackAdmission: ExtensionActionPopupCallbackAdmission
    private let browser: any ExtensionActionPopupBrowserProjection

    init(
        callbackAdmission: ExtensionActionPopupCallbackAdmission,
        browser: any ExtensionActionPopupBrowserProjection
    ) {
        self.callbackAdmission = callbackAdmission
        self.browser = browser
    }

    func capture(
        evidence: ExtensionActionPopupCallbackEvidence,
        target: ExtensionActionPopupPresentationTarget,
        popupWebView: WKWebView
    ) -> ExtensionActionPopupSourceReceipt? {
        let expectedWindowState = target.source.windowState
        guard let expectedTab = target.source.exactTab else { return nil }
        guard callbackAdmission.isCurrent(evidence),
              target.extensionID == evidence.extensionID,
              target.profileID == evidence.profileID,
              let windowState = browser.popupWindowState(id: target.windowID),
              windowState === expectedWindowState,
              browser.popupWindow(windowState, matches: evidence.profileID),
              let window = browser.popupAppKitWindow(for: windowState),
              let tab = browser.popupTab(id: expectedTab.id, in: windowState),
              tab === expectedTab,
              browser.popupProfileID(for: tab) == evidence.profileID,
              let profile = browser.popupProfile(id: evidence.profileID),
              tab.resolveProfile() === profile,
              popupWebView.configuration.websiteDataStore === profile.dataStore,
              popupWebView.configuration.webExtensionController
                  === evidence.controller
        else {
            return nil
        }

        return ExtensionActionPopupSourceReceipt(
            evidence: evidence,
            callbackAdmission: callbackAdmission,
            browser: browser,
            windowID: target.windowID,
            tabID: tab.id,
            windowState: windowState,
            window: window,
            tab: tab,
            profile: profile,
            popupWebView: popupWebView
        )
    }
}

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

    private let evidence: ExtensionActionPopupCallbackEvidence
    private let callbackAdmission: ExtensionActionPopupCallbackAdmission
    private let browser: any ExtensionActionPopupBrowserProjection
    private weak var windowState: BrowserWindowState?
    private weak var window: NSWindow?
    private weak var tab: Tab?
    private weak var popupWebView: WKWebView?
    private let profile: Profile
    private var isValid = true

    fileprivate init(
        evidence: ExtensionActionPopupCallbackEvidence,
        callbackAdmission: ExtensionActionPopupCallbackAdmission,
        browser: any ExtensionActionPopupBrowserProjection,
        windowID: UUID,
        tabID: UUID,
        windowState: BrowserWindowState,
        window: NSWindow,
        tab: Tab,
        profile: Profile,
        popupWebView: WKWebView
    ) {
        self.evidence = evidence
        self.callbackAdmission = callbackAdmission
        self.browser = browser
        self.extensionID = evidence.extensionID
        self.profileID = evidence.profileID
        self.windowID = windowID
        self.tabID = tabID
        self.windowState = windowState
        self.window = window
        self.tab = tab
        self.profile = profile
        self.popupWebView = popupWebView
    }

    func resolveFocusSource() -> ResolvedSource? {
        guard let popupWebView else { return nil }
        return resolveCurrentSource(popupWebView: popupWebView)
    }

    func invalidate() {
        isValid = false
    }

    private func resolveCurrentSource(
        popupWebView: WKWebView
    ) -> ResolvedSource? {
        guard isValid,
              callbackAdmission.isCurrent(evidence),
              self.popupWebView === popupWebView,
              popupWebView.configuration.websiteDataStore === profile.dataStore,
              popupWebView.configuration.webExtensionController
                  === evidence.controller,
              let expectedWindowState = windowState,
              let expectedWindow = window,
              let expectedTab = tab,
              browser.popupWindowState(id: windowID)
                  === expectedWindowState,
              browser.popupAppKitWindow(for: expectedWindowState)
                  === expectedWindow,
              browser.popupTab(id: tabID, in: expectedWindowState)
                  === expectedTab,
              browser.popupWindow(expectedWindowState, matches: profileID),
              browser.popupProfileID(for: expectedTab) == profileID,
              expectedTab.resolveProfile() === profile,
              browser.popupProfile(id: profileID) === profile
        else {
            return nil
        }
        return ResolvedSource(
            windowState: expectedWindowState,
            window: expectedWindow,
            tab: expectedTab
        )
    }
}
