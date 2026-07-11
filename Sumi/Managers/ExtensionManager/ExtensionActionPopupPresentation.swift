import AppKit
import SumiDomain
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupUIDelegate: NSObject, WKUIDelegate {
    private weak var manager: ExtensionManager?
    private weak var popover: NSPopover?
    private let sourceReceipt: ExtensionActionPopupSourceReceipt

    init(
        manager: ExtensionManager,
        popover: NSPopover,
        sourceReceipt: ExtensionActionPopupSourceReceipt
    ) {
        self.manager = manager
        self.popover = popover
        self.sourceReceipt = sourceReceipt
        super.init()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let manager else { return nil }
        return ExtensionActionPopupPresentation.createAuxiliaryWebViewFromActionPopup(
            webView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures,
            manager: manager,
            sourceReceipt: sourceReceipt
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
        guard let manager else {
            completionHandler(nil)
            return
        }
        completionHandler(ExtensionActionPopupPresentation
            .createAuxiliaryWebViewFromActionPopup(
                webView,
                with: configuration,
                for: navigationAction,
                windowFeatures: windowFeatures,
                manager: manager,
                sourceReceipt: sourceReceipt
            ))
    }

    func webViewDidClose(_ webView: WKWebView) {
        _ = webView
        guard let popover, popover.isShown else { return }
        popover.close()
    }
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionActionPopupPresentation {
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
        manager: ExtensionManager,
        sourceReceipt: ExtensionActionPopupSourceReceipt
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let windowPresentation = manager.extensionWindowPresentation,
              let source = sourceReceipt.resolve(
                popupWebView: popupWebView,
                childConfiguration: configuration,
                manager: manager
              )
        else {
            return nil
        }

        let sourceURL = navigationAction.sumiWebKitSourceURL ?? popupWebView.url
        let requestURL = navigationAction.request.url
        guard manager.ownerExtensionID(extensionOwnedSourceURL: sourceURL)
                == sourceReceipt.extensionID else {
            return nil
        }
        let resolvedOwnerExtensionID = sourceReceipt.extensionID

        if let requestURL,
           isExtensionExternalWebPopupURL(requestURL) {
            guard let extensionContext = manager.getExtensionContext(
                for: resolvedOwnerExtensionID,
                profileId: sourceReceipt.profileID
            ),
            manager.profileId(for: extensionContext)
                == sourceReceipt.profileID,
            let requestedWindow = manager.adapterResolutionOwner
                .publishedNormalWindowAdapter(
                    for: source.windowState,
                    extensionContext: extensionContext
                )
            else {
                return nil
            }
            let popupController =
                popupWebView.configuration.webExtensionController
                ?? configuration.webExtensionController
            let popupControllerProfileId = popupController.flatMap {
                manager.profileId(for: $0)
            }
            let profileId = sourceReceipt.profileID
            let controller =
                (popupControllerProfileId == profileId ? popupController : nil)
                ?? manager.ensureExtensionController(for: profileId)

            do {
                _ = try manager.requestedTabOpening.open(
                    url: requestURL,
                    shouldBeActive: true,
                    shouldBePinned: false,
                    requestedWindow: requestedWindow,
                    controller: controller,
                    extensionContext: extensionContext,
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

        return windowPresentation.presentExtensionExternalWebPopup(
            configuration: configuration,
            request: navigationAction.request,
            windowFeatures: windowFeatures,
            openerTab: source.tab,
            openerWindow: source.window,
            openerProfileID: sourceReceipt.profileID,
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
