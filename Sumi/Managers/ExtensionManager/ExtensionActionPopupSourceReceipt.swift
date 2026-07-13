import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupSourceAdmission {
    private let callbackAdmission: ExtensionActionPopupCallbackAdmission
    private let windowQuery: @MainActor () -> (any ExtensionWindowQuery)?
    private let currentProfile: @MainActor (UUID) -> Profile?
    private let resolvedProfileID: @MainActor (Tab) -> UUID?
    private let windowMatchesProfile: @MainActor (BrowserWindowState, UUID) -> Bool

    init(
        callbackAdmission: ExtensionActionPopupCallbackAdmission,
        windowQuery: @escaping @MainActor () -> (any ExtensionWindowQuery)?,
        currentProfile: @escaping @MainActor (UUID) -> Profile?,
        resolvedProfileID: @escaping @MainActor (Tab) -> UUID?,
        windowMatchesProfile: @escaping @MainActor (BrowserWindowState, UUID) -> Bool
    ) {
        self.callbackAdmission = callbackAdmission
        self.windowQuery = windowQuery
        self.currentProfile = currentProfile
        self.resolvedProfileID = resolvedProfileID
        self.windowMatchesProfile = windowMatchesProfile
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
              let windowQuery = windowQuery(),
              let windowState = windowQuery.extensionWindowState(
                  for: target.windowID
              ),
              windowState === expectedWindowState,
              windowMatchesProfile(windowState, evidence.profileID),
              let window = windowQuery.appKitWindow(for: windowState),
              let tab = windowQuery.extensionTab(
                  withID: expectedTab.id,
                  in: windowState
              ),
              tab === expectedTab,
              resolvedProfileID(tab) == evidence.profileID,
              let profile = currentProfile(evidence.profileID),
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
            windowQuery: self.windowQuery,
            currentProfile: currentProfile,
            resolvedProfileID: resolvedProfileID,
            windowMatchesProfile: windowMatchesProfile,
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
    private let windowQuery: @MainActor () -> (any ExtensionWindowQuery)?
    private let currentProfile: @MainActor (UUID) -> Profile?
    private let resolvedProfileID: @MainActor (Tab) -> UUID?
    private let windowMatchesProfile: @MainActor (BrowserWindowState, UUID) -> Bool
    private weak var windowState: BrowserWindowState?
    private weak var window: NSWindow?
    private weak var tab: Tab?
    private weak var popupWebView: WKWebView?
    private let profile: Profile
    private var isValid = true

    fileprivate init(
        evidence: ExtensionActionPopupCallbackEvidence,
        callbackAdmission: ExtensionActionPopupCallbackAdmission,
        windowQuery: @escaping @MainActor () -> (any ExtensionWindowQuery)?,
        currentProfile: @escaping @MainActor (UUID) -> Profile?,
        resolvedProfileID: @escaping @MainActor (Tab) -> UUID?,
        windowMatchesProfile: @escaping @MainActor (BrowserWindowState, UUID) -> Bool,
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
        self.windowQuery = windowQuery
        self.currentProfile = currentProfile
        self.resolvedProfileID = resolvedProfileID
        self.windowMatchesProfile = windowMatchesProfile
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
              let windowQuery = windowQuery(),
              windowQuery.extensionWindowState(for: windowID)
                  === expectedWindowState,
              windowQuery.appKitWindow(for: expectedWindowState)
                  === expectedWindow,
              windowQuery.extensionTab(withID: tabID, in: expectedWindowState)
                  === expectedTab,
              windowMatchesProfile(expectedWindowState, profileID),
              resolvedProfileID(expectedTab) == profileID,
              expectedTab.resolveProfile() === profile,
              currentProfile(profileID) === profile
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
