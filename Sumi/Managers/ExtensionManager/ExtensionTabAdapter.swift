//
//  ExtensionTabAdapter.swift
//  Sumi
//
//  WebKit bridge adapter that exposes Sumi tabs to WebExtensions.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabAdapter: NSObject, WKWebExtensionTab {
    let tabId: UUID

    private weak var browserContext: (any ExtensionBrowserBridgeContext)?
    private weak var extensionManager: ExtensionManager?

    init(
        tabId: UUID,
        browserContext: any ExtensionBrowserBridgeContext,
        extensionManager: ExtensionManager
    ) {
        self.tabId = tabId
        self.browserContext = browserContext
        self.extensionManager = extensionManager
        super.init()
    }

    var tab: Tab? {
        browserContext?.extensionTab(for: tabId)
    }

    private var tabUnavailableUntilReloadError: NSError {
        NSError(
            domain: "ExtensionTabAdapter",
            code: 3,
            userInfo: [
                NSLocalizedDescriptionKey: "Tab is not available to extensions until it is reloaded or navigates to a new document",
            ]
        )
    }

    private var tabUnavailableError: NSError {
        if tab != nil {
            return tabUnavailableUntilReloadError
        }
        return NSError(
            domain: "ExtensionTabAdapter",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Tab is no longer available"]
        )
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
        return browserContext?.preferredExtensionWindowState(containing: tab)
    }

    @discardableResult
    private func promoteTransientExtensionTabIfNeeded(_ tab: Tab) -> Bool {
        browserContext?.promoteTransientExtensionTab(tab) ?? false
    }

    func url(for _: WKWebExtensionContext) -> URL? {
        eligibleTab()?.url
    }

    func title(for _: WKWebExtensionContext) -> String? {
        eligibleTab()?.name
    }

    func isSelected(for _: WKWebExtensionContext) -> Bool {
        guard
            let browserContext,
            let tab = eligibleTab(),
            let windowState = resolvedWindowState()
        else {
            return false
        }

        return browserContext.currentExtensionTab(in: windowState)?.id == tab.id
    }

    func indexInWindow(for _: WKWebExtensionContext) -> Int {
        guard
            let browserContext,
            let tab = eligibleTab(),
            let windowState = resolvedWindowState()
        else {
            return 0
        }

        return browserContext.tabsForExtensionWindow(windowState)
            .firstIndex(where: { $0.id == tab.id }) ?? 0
    }

    func isLoadingComplete(for _: WKWebExtensionContext) -> Bool {
        !(eligibleTab()?.isLoading ?? false)
    }

    func isPinned(for _: WKWebExtensionContext) -> Bool {
        guard let tab = eligibleTab() else { return false }
        return browserContext?.isPinnedExtensionTab(tab) == true
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
        guard let browserContext, let tab = eligibleTab() else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableError
            )
            return
        }

        promoteTransientExtensionTabIfNeeded(tab)
        browserContext.selectExtensionTab(tab, in: resolvedWindowState())
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

        if let browserContext,
           browserContext.isAuxiliaryMiniWindowTab(tab),
           let webView = tab.existingWebView,
           browserContext.containsAuxiliaryWebView(webView) {
            browserContext.closeAuxiliaryWindowWebView(webView)
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
                error: NSError(
                    domain: "ExtensionTabAdapter",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No live web view is available for this tab"]
                )
            )
            return
        }

        let reloadTargetURL = webView.url ?? tab.url
        if tab.protectionAttachmentRequiresNormalWebViewRebuild(for: reloadTargetURL)
            || tab.autoplayPolicyRequiresNormalWebViewRebuild(for: reloadTargetURL) {
            tab.refresh()
        } else if fromOrigin {
            webView.reloadFromOrigin()
        } else {
            webView.reload()
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

    func window(for _: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard let tab = eligibleTab() else { return nil }
        if browserContext?.isAuxiliaryMiniWindowTab(tab) == true {
            return extensionManager?.miniWindowAdapter(for: tab)
        }
        if let miniWindowAdapter = extensionManager?.miniWindowAdapter(for: tab) {
            return miniWindowAdapter
        }
        guard let windowId = resolvedWindowState()?.id else { return nil }
        return extensionManager?.windowAdapter(for: windowId)
    }
}
