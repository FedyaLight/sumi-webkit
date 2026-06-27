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
              let browserManager = manager.browserManager
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

        guard let openerTab = browserManager.currentTabForActiveWindow()
            ?? browserManager.tabManager.currentTab
        else {
            return nil
        }

        if let requestURL,
           isExtensionExternalWebPopupURL(requestURL)
        {
            let profileId =
                manager.resolvedProfileId(for: openerTab)
                ?? manager.currentProfileId
                ?? browserManager.currentProfile?.id
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

        return browserManager.auxiliaryWindowManager.presentExtensionExternalWebPopup(
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
