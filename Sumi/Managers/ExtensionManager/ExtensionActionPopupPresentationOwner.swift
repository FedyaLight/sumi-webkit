import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupUIDelegate: NSObject, WKUIDelegate {
    private weak var manager: ExtensionManager?
    private weak var popover: NSPopover?

    init(manager: ExtensionManager, popover: NSPopover) {
        self.manager = manager
        self.popover = popover
        super.init()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        manager?.createAuxiliaryWebViewFromActionPopup(
            webView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures
        )
    }

    @objc(_webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:completionHandler:)
    func webView(
        _ webView: WKWebView,
        createWebViewWithConfiguration configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures,
        completionHandler: @escaping (WKWebView?) -> Void
    ) {
        completionHandler(
            manager?.createAuxiliaryWebViewFromActionPopup(
                webView,
                with: configuration,
                for: navigationAction,
                windowFeatures: windowFeatures
            )
        )
    }

    func webViewDidClose(_ webView: WKWebView) {
        _ = webView
        guard let popover, popover.isShown else { return }
        popover.close()
    }
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionActionPopupPresentationOwner {
    static let minimumContentSize = NSSize(width: 320, height: 480)

    static func prepare(_ popover: NSPopover) {
        if popover.contentSize.width < 8 || popover.contentSize.height < 8 {
            popover.contentSize = minimumContentSize
        }
    }

    static func anchorRect(for anchorView: NSView) -> CGRect {
        let bounds = anchorView.bounds
        guard bounds.width < 4 || bounds.height < 4 else {
            return bounds
        }
        let side = max(28, max(bounds.width, bounds.height))
        return CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
    }

    static func show(
        _ popover: NSPopover,
        relativeTo anchorView: NSView,
        preferredEdge: NSRectEdge
    ) {
        prepare(popover)
        popover.show(
            relativeTo: anchorRect(for: anchorView),
            of: anchorView,
            preferredEdge: preferredEdge
        )
    }

    static func createAuxiliaryWebViewFromActionPopup(
        _ popupWebView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures,
        manager: ExtensionManager
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let browserContext = manager.browserBridgeContext
        else {
            return nil
        }

        let sourceURL = navigationAction.sumiWebKitSourceURL ?? popupWebView.url
        let requestURL = navigationAction.request.url
        let resolvedOwnerExtensionID = manager.ownerExtensionID(extensionOwnedSourceURL: sourceURL)
            ?? manager.ownerExtensionID(extensionOwnedSourceURL: requestURL)
            ?? manager.activePopupExtensionID

        guard resolvedOwnerExtensionID != nil
            || Tab.isExtensionOriginatedPopupNavigation(
                sourceURL: sourceURL,
                requestURL: requestURL
            )
        else {
            return nil
        }

        guard let openerTab = browserContext.currentExtensionTabForPopup() else {
            return nil
        }

        if let requestURL,
           isExtensionExternalWebPopupURL(requestURL) {
            let profileId =
                manager.resolvedProfileId(for: openerTab)
                ?? manager.currentProfileId
                ?? manager.browserManager?.currentProfile?.id
            let controller =
                popupWebView.configuration.webExtensionController
                ?? configuration.webExtensionController
                ?? profileId.map { manager.ensureExtensionController(for: $0) }
            guard let controller else { return nil }

            do {
                _ = try manager.openExtensionRequestedTab(
                    url: requestURL,
                    shouldBeActive: true,
                    shouldBePinned: false,
                    requestedWindow: nil,
                    controller: controller,
                    extensionContext: resolvedOwnerExtensionID.flatMap {
                        manager.getExtensionContext(for: $0, profileId: profileId)
                    },
                    reason: "ExtensionManager.createNormalTabFromActionPopupExternalURL"
                )
                return nil
            } catch {
                RuntimeDiagnostics.debug(category: "SafariExtensionPermissions") {
                    "Failed to open extension external URL in normal tab: \(error.localizedDescription)"
                }
                return nil
            }
        }

        return browserContext.presentExtensionExternalWebPopup(
            configuration: configuration,
            request: navigationAction.request,
            windowFeatures: windowFeatures,
            openerTab: openerTab,
            shouldActivateApp: true,
            extensionOwnedSourceURL: sourceURL,
            ownerExtensionID: resolvedOwnerExtensionID
        )
    }

    nonisolated static func isExtensionExternalWebPopupURL(_ url: URL?) -> Bool {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              ExtensionUtils.isExtensionOwnedURL(url) == false
        else {
            return false
        }

        return true
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager: NSPopoverDelegate {
    func restoreInlineUIHostingFocusIfNeeded() {
        guard SafariExtensionAutofillFillDiagnostics
            .shouldRestoreInlineUIHostingFocusAfterPopupClose()
        else {
            return
        }
        guard let tab = browserBridgeContext?.currentExtensionTabForActiveWindow(),
              let webView = resolvedLiveWebView(for: tab),
              let window = webView.window,
              webView.superview != nil
        else {
            return
        }
        guard !webView.sumiIsInFullscreenElementPresentation else { return }

        DispatchQueue.main.async { [weak webView, weak window] in
            guard let webView, let window else { return }
            guard window.firstResponder !== webView else { return }
            _ = window.makeFirstResponder(webView)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        isPopupActive = false
        activeExtensionActionPopover = nil
        if let extensionId = activePopupExtensionID {
            SafariExtensionAutofillFillDiagnostics.setPopupActive(false, extensionId: extensionId)
            restoreInlineUIHostingFocusIfNeeded()
            SafariExtensionAutofillFillDiagnostics.logSnapshotIfEnabled(
                context: "popoverDidClose"
            )
            let profileId = browserManager?.currentProfile?.id
            SumiNativeMessagingRuntimeCounters.recordPopupClosed(extensionId: extensionId)
            extensionActionPopupUIDelegates.removeValue(forKey: extensionId)
            scheduleOrPerformDeferredPopupContextUnload(
                forExtensionId: extensionId,
                profileId: profileId
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                let diagnostic = await SafariExtensionSessionDiagnosticsBuilder.build(
                    extensionId: extensionId,
                    phase: .closed,
                    extensionManager: self
                )
                SafariExtensionSessionDiagnosticsBuilder.logIfDiagnosticsEnabled(diagnostic)
                if SafariExtensionAutofillFillDiagnostics.shouldDeferNativeMessagingTeardownOnPopupClose()
                    == false {
                    self.activePopupExtensionID = nil
                }
            }
        }
    }

    func performExtensionPopupContextUnload(
        forExtensionId extensionId: String,
        profileId: UUID?
    ) {
        safariNativeMessagingHost.clearLaunchSessionOnExtensionContextUnload(
            forExtensionId: extensionId,
            profileId: profileId
        )
        pruneNativeMessagePortHandlerEntries(
            forExtensionId: extensionId,
            profileId: profileId
        )
    }

    func scheduleOrPerformDeferredPopupContextUnload(
        forExtensionId extensionId: String,
        profileId: UUID?
    ) {
        if SafariExtensionAutofillFillDiagnostics.shouldDeferNativeMessagingTeardownOnPopupClose() {
            scheduleDeferredPopupContextUnload(
                forExtensionId: extensionId,
                profileId: profileId
            )
            return
        }
        SafariExtensionAutofillFillDiagnostics.endFillSession(extensionId: extensionId)
        performExtensionPopupContextUnload(
            forExtensionId: extensionId,
            profileId: profileId
        )
        activePopupExtensionID = nil
    }

    func scheduleDeferredPopupContextUnload(
        forExtensionId extensionId: String,
        profileId: UUID?
    ) {
        cancelDeferredPopupContextUnload(forExtensionId: extensionId)
        deferredPopupContextUnloadProfileIDs[extensionId] = profileId
        deferredPopupContextUnloadTasks[extensionId] = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: SafariExtensionAutofillFillDiagnostics.deferredFillTeardownTimeout
            )
            guard !Task.isCancelled else { return }
            self?.completeDeferredPopupContextUnload(
                forExtensionId: extensionId,
                reason: "timeout"
            )
        }
    }

    func completeDeferredPopupContextUnload(
        forExtensionId extensionId: String,
        reason: String
    ) {
        cancelDeferredPopupContextUnload(forExtensionId: extensionId)
        SafariExtensionAutofillFillDiagnostics.beginIntentionalDeferredTeardown()
        defer {
            SafariExtensionAutofillFillDiagnostics.endIntentionalDeferredTeardown()
        }
        SafariExtensionAutofillFillDiagnostics.endFillSession(extensionId: extensionId)
        let profileId = deferredPopupContextUnloadProfileIDs.removeValue(forKey: extensionId)
        performExtensionPopupContextUnload(
            forExtensionId: extensionId,
            profileId: profileId
        )
        activePopupExtensionID = nil
        SafariExtensionAutofillFillDiagnostics.logSnapshotIfEnabled(
            context: "deferredPopupContextUnload:\(reason)"
        )
    }

    func cancelDeferredPopupContextUnload(forExtensionId extensionId: String) {
        deferredPopupContextUnloadTasks[extensionId]?.cancel()
        deferredPopupContextUnloadTasks.removeValue(forKey: extensionId)
    }

    func recordExtensionActionPopupPresentation(
        for extensionId: String,
        popupWebView: WKWebView?,
        phase: SafariExtensionPopupLifecyclePhase
    ) {
        if phase == .opened || phase == .reopened {
            SumiNativeMessagingRuntimeCounters.recordPopupOpened(extensionId: extensionId)
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let diagnostic = await SafariExtensionSessionDiagnosticsBuilder.build(
                extensionId: extensionId,
                phase: phase,
                extensionManager: self,
                popupWebView: popupWebView
            )
            SafariExtensionSessionDiagnosticsBuilder.logIfDiagnosticsEnabled(diagnostic)
        }
    }
}
