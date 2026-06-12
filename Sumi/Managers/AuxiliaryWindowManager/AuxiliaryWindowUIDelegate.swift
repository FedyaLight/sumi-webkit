//
//  AuxiliaryWindowUIDelegate.swift
//  Sumi
//

import AppKit
import WebKit

@MainActor
final class AuxiliaryWindowUIDelegate: NSObject, WKUIDelegate {
    private weak var manager: AuxiliaryWindowManager?
    private weak var openerTab: Tab?
    private let nestedDepth: Int

    init(manager: AuxiliaryWindowManager, openerTab: Tab?, nestedDepth: Int) {
        self.manager = manager
        self.openerTab = openerTab
        self.nestedDepth = nestedDepth
    }

    func webViewDidClose(_ webView: WKWebView) {
        manager?.teardown(for: webView, reason: .webViewDidClose)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        let isSizedPopup = windowFeatures.width != nil

        if isSizedPopup {
            guard let manager, let openerTab else { return nil }
            guard nestedDepth < manager.maxNestedDepth else {
                RuntimeDiagnostics.emit(
                    "🪟 [AuxiliaryWindowUIDelegate] Blocked nested sized popup at depth \(nestedDepth + 1); max depth is \(manager.maxNestedDepth)"
                )
                return nil
            }

            let parentSession = manager.session(for: openerTab)
            let ownerExtensionID = parentSession?.ownerExtensionID
            let isExtensionOriginated = ownerExtensionID != nil
                || Tab.isExtensionOriginatedExternalPopupNavigation(
                    sourceURL: navigationAction.sumiWebKitSourceURL ?? openerTab.url,
                    requestURL: navigationAction.request.url
                )

            return manager.presentWebPopup(
                configuration: configuration,
                request: navigationAction.request,
                windowFeatures: windowFeatures,
                openerTab: openerTab,
                isExtensionOriginated: isExtensionOriginated,
                shouldActivateApp: true,
                nestedDepth: nestedDepth + 1,
                ownerExtensionID: ownerExtensionID,
                extensionOwnedSourceURL: navigationAction.sumiWebKitSourceURL ?? openerTab.url
            )
        }

        // Unsized nested popups keep the configured in-place load policy.
        webView.load(navigationAction.request)
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        if let window = webView.window {
            panel.beginSheetModal(for: window) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        } else {
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        if let window = webView.window {
            alert.beginSheetModal(for: window) { _ in completionHandler() }
        } else {
            alert.runModal()
            completionHandler()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if let window = webView.window {
            alert.beginSheetModal(for: window) { response in
                completionHandler(response == .alertFirstButtonReturn)
            }
        } else {
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input
        if let window = webView.window {
            alert.beginSheetModal(for: window) { response in
                completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
            }
        } else {
            completionHandler(alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }
}
