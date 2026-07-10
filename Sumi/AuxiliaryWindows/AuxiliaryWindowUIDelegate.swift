//
//  AuxiliaryWindowUIDelegate.swift
//  Sumi
//

import AppKit
import WebKit
import SumiDomain

@MainActor
final class AuxiliaryWindowUIDelegate: NSObject, WKUIDelegate {
    private weak var sessions: AuxiliaryWindowSessionRegistry?
    private weak var popups: AuxiliaryPopupOpeningService?
    private weak var teardown: AuxiliaryWindowTeardownService?
    private weak var permissions: (any AuxiliaryWindowPermissionHandling)?
    private let nestingPolicy: AuxiliaryWindowNestingPolicy
    private weak var openerTab: Tab?
    private let nestedDepth: Int

    init(
        sessions: AuxiliaryWindowSessionRegistry,
        popups: AuxiliaryPopupOpeningService,
        teardown: AuxiliaryWindowTeardownService,
        permissions: any AuxiliaryWindowPermissionHandling,
        nestingPolicy: AuxiliaryWindowNestingPolicy,
        openerTab: Tab?,
        nestedDepth: Int
    ) {
        self.sessions = sessions
        self.popups = popups
        self.teardown = teardown
        self.permissions = permissions
        self.nestingPolicy = nestingPolicy
        self.openerTab = openerTab
        self.nestedDepth = nestedDepth
    }

    func webViewDidClose(_ webView: WKWebView) {
        teardown?.teardown(for: webView, reason: .webViewDidClose)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        let isSizedPopup = windowFeatures.width != nil
            || windowFeatures.height != nil
            || windowFeatures.sumiOrigin != nil

        if isSizedPopup {
            guard let popups,
                  let sourceTab = sessions?.session(for: webView)?.tab
                    ?? openerTab
            else { return nil }
            guard let childDepth = nestingPolicy.childDepth(
                after: nestedDepth
            ) else {
                RuntimeDiagnostics.emit(
                    "🪟 [AuxiliaryWindowUIDelegate] Blocked nested sized popup at depth \(nestedDepth + 1); max depth is \(nestingPolicy.maximumDepth)"
                )
                return nil
            }

            let parentSession = sessions?.session(for: webView)
            let ownerExtensionID = parentSession?.ownerExtensionID
            let isExtensionOriginated = ownerExtensionID != nil
                || SumiPopupNavigationOrigin.isExtensionOriginatedExternalPopupNavigation(
                    sourceURL: navigationAction.sumiWebKitSourceURL ?? sourceTab.url,
                    requestURL: navigationAction.request.url
                )
            guard let tabContext = sourceTab.popupPermissionTabContext(for: webView) else {
                return nil
            }
            let activationState = sourceTab.popupUserActivationTracker.activationState(
                webKitUserInitiated: navigationAction.isUserInitiated
            )
            let request = SumiPopupPermissionRequest.fromWKNavigationAction(
                navigationAction,
                path: .uiDelegateCreateWebView,
                activationState: activationState,
                isExtensionOriginated: isExtensionOriginated
            )
            guard let permissionResult = permissions?.evaluatePopupPermission(
                request,
                tabContext: tabContext
            ) else {
                return nil
            }
            guard permissionResult.isAllowed else { return nil }
            sourceTab.popupUserActivationTracker.consumeIfUserActivated(request.userActivation)

            return popups.presentWebPopup(
                configuration: configuration,
                request: navigationAction.request,
                windowFeatures: windowFeatures,
                openerTab: sourceTab,
                isExtensionOriginated: isExtensionOriginated,
                shouldActivateApp: true,
                nestedDepth: childDepth,
                ownerExtensionID: ownerExtensionID,
                extensionOwnedSourceURL: navigationAction.sumiWebKitSourceURL ?? sourceTab.url
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
        guard let tab = sessions?.session(for: webView)?.tab,
              let tabContext = tab.filePickerPermissionTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit("📁 [AuxiliaryWindowUIDelegate] Denying file picker because browser/profile context is unavailable.")
            completionHandler(nil)
            return
        }

        let activationState = tab.popupUserActivationTracker.activationState(webKitUserInitiated: nil)
        let request = SumiFilePickerPermissionRequest(
            parameters: parameters,
            frame: frame,
            userActivation: activationState
        )
        let didHandleOpenPanel = permissions?.handleFilePickerOpenPanel(
            request,
            tabContext: tabContext,
            webView: webView,
            currentPageID: { [weak tab] in tab?.currentPermissionPageId() },
            completionHandler: completionHandler
        ) ?? false
        guard didHandleOpenPanel else {
            RuntimeDiagnostics.emit("📁 [AuxiliaryWindowUIDelegate] Denying file picker because permission runtime is unavailable.")
            completionHandler(nil)
            return
        }
        tab.popupUserActivationTracker.consumeIfUserActivated(activationState)
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
