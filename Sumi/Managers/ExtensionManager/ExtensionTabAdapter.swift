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

    private weak var windowQuery: (any ExtensionWindowQuery)?
    private weak var tabQuery: (any ExtensionTabQuery)?
    private weak var tabMutation: (any ExtensionTabMutation)?
    private weak var webViewHosting: (any ExtensionTabWebViewHosting)?
    private weak var auxiliaryWindows: (any ExtensionAuxiliaryWindowControl)?
    private weak var extensionManager: ExtensionManager?

    init(
        tabId: UUID,
        windowQuery: any ExtensionWindowQuery,
        tabQuery: any ExtensionTabQuery,
        tabMutation: any ExtensionTabMutation,
        webViewHosting: any ExtensionTabWebViewHosting,
        auxiliaryWindows: any ExtensionAuxiliaryWindowControl,
        extensionManager: ExtensionManager
    ) {
        self.tabId = tabId
        self.windowQuery = windowQuery
        self.tabQuery = tabQuery
        self.tabMutation = tabMutation
        self.webViewHosting = webViewHosting
        self.auxiliaryWindows = auxiliaryWindows
        self.extensionManager = extensionManager
        super.init()
    }

    var tab: Tab? {
        tabQuery?.extensionTab(for: tabId)
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

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionTabAdapter else { return false }
        return other.tabId == tabId
    }

    override var hash: Int {
        tabId.hashValue
    }

    private func resolvedWindowState() -> BrowserWindowState? {
        guard let tab else { return nil }
        return windowQuery?.preferredExtensionWindowState(containing: tab)
    }

    @discardableResult
    private func promoteTransientExtensionTabIfNeeded(_ tab: Tab) -> Bool {
        tabMutation?.promoteTransientExtensionTab(tab) ?? false
    }

    func url(for _: WKWebExtensionContext) -> URL? {
        eligibleTab()?.url
    }

    func title(for _: WKWebExtensionContext) -> String? {
        eligibleTab()?.name
    }

    func isSelected(for _: WKWebExtensionContext) -> Bool {
        guard
            let windowQuery,
            let tab = eligibleTab(),
            let windowState = resolvedWindowState()
        else {
            return false
        }

        return windowQuery.currentExtensionTab(in: windowState)?.id == tab.id
    }

    func indexInWindow(for _: WKWebExtensionContext) -> Int {
        guard
            let windowQuery,
            let tab = eligibleTab(),
            let windowState = resolvedWindowState()
        else {
            return 0
        }

        return windowQuery.tabsForExtensionWindow(windowState)
            .firstIndex(where: { $0.id == tab.id }) ?? 0
    }

    func isLoadingComplete(for _: WKWebExtensionContext) -> Bool {
        !(eligibleTab()?.isLoading ?? false)
    }

    func isPinned(for _: WKWebExtensionContext) -> Bool {
        guard let tab = eligibleTab() else { return false }
        return tabQuery?.isPinnedExtensionTab(tab) == true
    }

    func isMuted(for _: WKWebExtensionContext) -> Bool {
        eligibleTab()?.audioState.isMuted ?? false
    }

    func isPlayingAudio(for _: WKWebExtensionContext) -> Bool {
        eligibleTab()?.audioState.isPlayingAudio ?? false
    }

    func isReaderModeActive(for _: WKWebExtensionContext) -> Bool {
        false
    }

    func webView(for extensionContext: WKWebExtensionContext) -> WKWebView? {
        guard let tab = eligibleTab(),
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
        for _: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tabMutation, let tab = eligibleTab() else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableError
            )
            return
        }

        guard let windowState = resolvedWindowState() else {
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
        for _: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab() else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableUntilReloadError
            )
            return
        }

        if tabQuery?.isAuxiliaryMiniWindowTab(tab) == true,
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
        guard let tab = eligibleTab() else {
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
            in: resolvedWindowState(),
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
        for _: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab() else {
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
        for _: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab() else {
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

    func shouldGrantPermissionsOnUserGesture(for _: WKWebExtensionContext) -> Bool {
        true
    }

    func shouldBypassPermissions(for _: WKWebExtensionContext) -> Bool {
        false
    }

    func window(
        for extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        guard let tab = eligibleTab() else { return nil }
        if tabQuery?.isAuxiliaryMiniWindowTab(tab) == true {
            return extensionManager?.adapterResolutionOwner.miniWindowAdapter(for: tab)
        }
        if let miniWindowAdapter = extensionManager?.adapterResolutionOwner.miniWindowAdapter(for: tab) {
            return miniWindowAdapter
        }
        guard let extensionManager,
              let profileID = extensionManager.profileId(for: extensionContext),
              extensionManager.resolvedProfileId(for: tab) == profileID,
              let windowState = resolvedWindowState()
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
