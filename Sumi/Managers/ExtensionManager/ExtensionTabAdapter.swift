//
//  ExtensionTabAdapter.swift
//  Sumi
//
//  WebKit bridge adapter that exposes Sumi tabs to WebExtensions.
//

import Foundation
import SumiWebRuntime
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabAdapter: NSObject, WKWebExtensionTab {
    let tabId: UUID

    private weak var exactTab: Tab?
    private weak var windowQuery: (any ExtensionWindowQuery)?
    private weak var tabQuery: (any ExtensionTabQuery)?
    private weak var tabMutation: (any ExtensionTabMutation)?
    private weak var webViewHosting: (any ExtensionTabWebViewHosting)?
    private weak var auxiliaryWindows: (any ExtensionAuxiliaryWindowControl)?
    private weak var windowPublications: ExtensionWindowPublicationQuery?
    private weak var contextPublications: ExtensionContextPublicationQuery?
    private weak var extensionManager: ExtensionManager?
    private let requiresAuxiliaryPublication: Bool

    init(
        tab: Tab,
        windowQuery: any ExtensionWindowQuery,
        tabQuery: any ExtensionTabQuery,
        tabMutation: any ExtensionTabMutation,
        webViewHosting: any ExtensionTabWebViewHosting,
        auxiliaryWindows: any ExtensionAuxiliaryWindowControl,
        windowPublications: ExtensionWindowPublicationQuery,
        contextPublications: ExtensionContextPublicationQuery,
        extensionManager: ExtensionManager
    ) {
        self.tabId = tab.id
        self.exactTab = tab
        self.windowQuery = windowQuery
        self.tabQuery = tabQuery
        self.tabMutation = tabMutation
        self.webViewHosting = webViewHosting
        self.auxiliaryWindows = auxiliaryWindows
        self.windowPublications = windowPublications
        self.contextPublications = contextPublications
        self.extensionManager = extensionManager
        requiresAuxiliaryPublication = tab.isAuxiliaryMiniWindow
            || tabQuery.isAuxiliaryMiniWindowTab(tab)
        super.init()
    }

    var tab: Tab? {
        guard let exactTab,
              tabQuery?.extensionTab(for: tabId) === exactTab else {
            return nil
        }
        return exactTab
    }

    func represents(_ tab: Tab) -> Bool {
        exactTab === tab && tabQuery?.extensionTab(for: tabId) === tab
    }

    /// Physical identity remains valid after the Tab leaves browser
    /// collections. Teardown receipts use it to retire the exact adapter
    /// without granting the detached Tab any live WebExtension capability.
    func hasExactTabIdentity(_ tab: Tab) -> Bool {
        exactTab === tab
    }

    func canBeReplaced(by tab: Tab) -> Bool {
        exactTab !== tab && tabQuery?.extensionTab(for: tabId) === tab
    }

    private var tabUnavailableUntilReloadError: NSError {
        ExtensionBridgeAdapterCallbackError.tabUnavailableUntilReload.nsError()
    }

    private var tabUnavailableError: NSError {
        if tab != nil {
            return tabUnavailableUntilReloadError
        }
        return ExtensionBridgeAdapterCallbackError.tabUnavailable.nsError()
    }

    private func eligibleTab() -> Tab? {
        guard let tab, extensionManager?.isTabEligibleForCurrentExtensionRuntime(tab) == true else {
            return nil
        }
        return tab
    }

    /// Normal Tabs retain their existing profile/controller eligibility. An
    /// auxiliary Tab additionally requires the exact committed owner-context
    /// publication; a same-profile unrelated extension cannot observe or act
    /// on the adapter merely because it knows the Tab UUID.
    private func eligibleTab(
        for extensionContext: WKWebExtensionContext
    ) -> Tab? {
        guard let identity = contextPublications?.currentIdentity(
                for: extensionContext
              ),
              let tab = eligibleTab()
        else {
            return nil
        }
        guard isAuxiliaryTab(tab) else {
            guard extensionManager?.resolvedProfileId(for: tab)
                    == identity.profileID,
                  windowPublications?.tabPublicationIsCurrent(
                    tab,
                    profileID: identity.profileID
                  ) == true
            else {
                return nil
            }
            return tab
        }
        guard windowPublications?.isCommittedAuxiliaryTabAdapter(
            self,
            for: tab,
            visibleTo: extensionContext
        ) == true else {
            return nil
        }
        return tab
    }

    private func isAuxiliaryTab(_ tab: Tab) -> Bool {
        requiresAuxiliaryPublication
            || tab.isAuxiliaryMiniWindow
            || tabQuery?.isAuxiliaryMiniWindowTab(tab) == true
            || windowPublications?.isAuxiliarySessionTab(tab) == true
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionTabAdapter else {
            return false
        }
        return other === self
    }

    override var hash: Int {
        ObjectIdentifier(self).hashValue
    }

    private func resolvedWindowState(for tab: Tab) -> BrowserWindowState? {
        return windowQuery?.preferredExtensionWindowState(containing: tab)
    }

    @discardableResult
    private func promoteTransientExtensionTabIfNeeded(_ tab: Tab) -> Bool {
        tabMutation?.promoteTransientExtensionTab(tab) ?? false
    }

    func url(for extensionContext: WKWebExtensionContext) -> URL? {
        eligibleTab(for: extensionContext)?.url
    }

    func title(for extensionContext: WKWebExtensionContext) -> String? {
        eligibleTab(for: extensionContext)?.name
    }

    func isSelected(for extensionContext: WKWebExtensionContext) -> Bool {
        guard
            let windowQuery,
            let tab = eligibleTab(for: extensionContext),
            let windowState = resolvedWindowState(for: tab)
        else {
            return false
        }

        return windowQuery.currentExtensionTab(in: windowState)?.id == tab.id
    }

    func indexInWindow(for extensionContext: WKWebExtensionContext) -> Int {
        guard
            let windowQuery,
            let tab = eligibleTab(for: extensionContext),
            let windowState = resolvedWindowState(for: tab)
        else {
            return 0
        }

        return windowQuery.tabsForExtensionWindow(windowState)
            .firstIndex(where: { $0.id == tab.id }) ?? 0
    }

    func isLoadingComplete(for extensionContext: WKWebExtensionContext) -> Bool {
        eligibleTab(for: extensionContext)?.isLoading == false
    }

    func isPinned(for extensionContext: WKWebExtensionContext) -> Bool {
        guard let tab = eligibleTab(for: extensionContext) else { return false }
        return tabQuery?.isPinnedExtensionTab(tab) == true
    }

    func isMuted(for extensionContext: WKWebExtensionContext) -> Bool {
        eligibleTab(for: extensionContext)?.audioState.isMuted ?? false
    }

    func isPlayingAudio(for extensionContext: WKWebExtensionContext) -> Bool {
        eligibleTab(for: extensionContext)?.audioState.isPlayingAudio ?? false
    }

    func isReaderModeActive(for _: WKWebExtensionContext) -> Bool {
        false
    }

    func webView(for extensionContext: WKWebExtensionContext) -> WKWebView? {
        guard let tab = eligibleTab(for: extensionContext),
              let extensionManager
        else {
            SafariExtensionAutofillFillDiagnostics.recordFrameResolution(
                resolved: false,
                extensionId: extensionManager?.extensionID(for: extensionContext),
                reason: "tabAdapterWebViewUnavailable"
            )
            return nil
        }
        let webView = extensionManager.extensionWebView(
            for: tab,
            extensionContext: extensionContext
        )
        SafariExtensionAutofillFillDiagnostics.recordFrameResolution(
            resolved: webView != nil,
            extensionId: extensionManager.extensionID(for: extensionContext),
            reason: "tabAdapterWebView"
        )
        return webView
    }

    func activate(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tabMutation,
              let tab = eligibleTab(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableError
            )
            return
        }

        guard let windowState = resolvedWindowState(for: tab) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError.tabWindowUnavailable.nsError()
            )
            return
        }

        promoteTransientExtensionTabIfNeeded(tab)
        tabMutation.selectExtensionTab(tab, in: windowState)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
    }

    func close(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableUntilReloadError
            )
            return
        }

        if isAuxiliaryTab(tab),
           let auxiliaryWindows,
           let webView = auxiliaryWindows.auxiliaryWindowSession(for: tab)?.webView,
           auxiliaryWindows.containsAuxiliaryWebView(webView) {
            auxiliaryWindows.closeAuxiliaryWindowWebView(webView)
            ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
            return
        }

        tab.closeTab()
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
    }

    func reload(
        fromOrigin: Bool,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableUntilReloadError
            )
            return
        }
        guard let webView = webView(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError.tabWebViewUnavailable.nsError()
            )
            return
        }

        guard let webViewHosting else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableError
            )
            return
        }
        let outcome = webViewHosting.reloadExtensionTab(
            tab,
            webView: webView,
            in: resolvedWindowState(for: tab),
            policy: fromOrigin ? .fromOrigin : .standard
        )
        if outcome == .failed {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError.tabReloadFailed.nsError()
            )
            return
        }

        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
    }

    func loadURL(
        _ url: URL,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableUntilReloadError
            )
            return
        }
        if ExtensionUtils.isExtensionOwnedURL(url) == false {
            promoteTransientExtensionTabIfNeeded(tab)
        }
        tab.loadURL(url)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
    }

    func setMuted(
        _ muted: Bool,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableUntilReloadError
            )
            return
        }
        tab.setMuted(muted)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
    }

    func setZoomFactor(
        _ zoomFactor: Double,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let webView = webView(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableError
            )
            return
        }
        webView.pageZoom = zoomFactor
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
    }

    func zoomFactor(for extensionContext: WKWebExtensionContext) -> Double {
        Double(webView(for: extensionContext)?.pageZoom ?? 1)
    }

    func shouldGrantPermissionsOnUserGesture(
        for extensionContext: WKWebExtensionContext
    ) -> Bool {
        return eligibleTab(for: extensionContext) != nil
    }

    func shouldBypassPermissions(for _: WKWebExtensionContext) -> Bool {
        false
    }

    func window(
        for extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        guard let tab = eligibleTab(for: extensionContext) else { return nil }
        if isAuxiliaryTab(tab) {
            return extensionManager?.adapterResolutionOwner.miniWindowAdapter(for: tab)
        }
        if let miniWindowAdapter = extensionManager?.adapterResolutionOwner.miniWindowAdapter(for: tab) {
            return miniWindowAdapter
        }
        guard let extensionManager,
              let profileID = contextPublications?.currentIdentity(
                for: extensionContext
              )?.profileID,
              extensionManager.resolvedProfileId(for: tab) == profileID,
              let windowState = resolvedWindowState(for: tab)
        else {
            return nil
        }
        return extensionManager.adapterResolutionOwner
            .publishedNormalWindowAdapter(
                for: windowState,
                extensionContext: extensionContext
            )
    }
}
