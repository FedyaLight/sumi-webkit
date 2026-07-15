//
//  AuxiliaryWindowUIDelegate.swift
//  Sumi
//

import AppKit
import SumiDomain
import WebKit

@MainActor
final class AuxiliaryWindowUIDelegate: NSObject, WKUIDelegate {
    private weak var sessions: AuxiliaryWindowSessionRegistry?
    private weak var popups: AuxiliaryPopupOpeningService?
    private weak var teardown: AuxiliaryWindowTeardownService?
    private weak var permissions: (any AuxiliaryWindowPermissionHandling)?
    private let nestingPolicy: AuxiliaryWindowNestingPolicy
    private let nestedDepth: Int
    private var sessionReceipt: AuxiliaryWindowSessionReceipt?

    init(
        sessions: AuxiliaryWindowSessionRegistry,
        popups: AuxiliaryPopupOpeningService,
        teardown: AuxiliaryWindowTeardownService,
        permissions: any AuxiliaryWindowPermissionHandling,
        nestingPolicy: AuxiliaryWindowNestingPolicy,
        nestedDepth: Int
    ) {
        self.sessions = sessions
        self.popups = popups
        self.teardown = teardown
        self.permissions = permissions
        self.nestingPolicy = nestingPolicy
        self.nestedDepth = nestedDepth
    }

    func bind(_ receipt: AuxiliaryWindowSessionReceipt) {
        precondition(sessionReceipt == nil)
        sessionReceipt = receipt
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard currentSession(for: webView) != nil,
              let sessionReceipt
        else { return }
        teardown?.teardown(sessionReceipt, reason: .webViewDidClose)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let session = currentSession(for: webView)
        else { return nil }

        let isSizedPopup = windowFeatures.width != nil
            || windowFeatures.height != nil
            || windowFeatures.sumiOrigin != nil

        if isSizedPopup {
            guard let sourceWebView = webView as? FocusableWKWebView,
                  let popups
            else { return nil }
            let sourceTab = session.tab
            guard let childDepth = nestingPolicy.childDepth(
                after: nestedDepth
            ) else {
                RuntimeDiagnostics.emit(
                    "🪟 [AuxiliaryWindowUIDelegate] Blocked nested sized popup at depth \(nestedDepth + 1); max depth is \(nestingPolicy.maximumDepth)"
                )
                return nil
            }

            let ownerExtensionID = session.ownerExtensionID
            let sourceDocumentURL = navigationAction.sumiWebKitSourceURL
                ?? sourceWebView.committedURL
                ?? sourceWebView.url
            let isExtensionOriginated = ownerExtensionID != nil
                || SumiPopupNavigationOrigin.isExtensionOriginatedExternalPopupNavigation(
                    sourceURL: sourceDocumentURL,
                    requestURL: navigationAction.request.url
                )
            guard let tabContext = sourceTab.popupPermissionTabContext(for: webView) else {
                return nil
            }
            let activationState = sourceWebView.popupUserActivation.claim(
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
            guard permissionResult.isAllowed,
                  currentSession(for: webView) === session
            else { return nil }
            return popups.presentWebPopup(
                configuration: configuration,
                request: navigationAction.request,
                windowFeatures: windowFeatures,
                openerTab: sourceTab,
                explicitOpenerWindow: session.window,
                explicitOpenerProfileID: sourceTab.profileId
                    ?? sourceTab.resolveProfile()?.id,
                isExtensionOriginated: isExtensionOriginated,
                shouldActivateApp: true,
                nestedDepth: childDepth,
                ownerExtensionID: ownerExtensionID,
                extensionOwnedSourceURL: sourceDocumentURL
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
        guard let sourceWebView = webView as? FocusableWKWebView,
              let session = currentSession(for: webView),
              let tabContext = session.tab.filePickerPermissionTabContext(
                  for: webView
              )
        else {
            RuntimeDiagnostics.emit("📁 [AuxiliaryWindowUIDelegate] Denying file picker because browser/profile context is unavailable.")
            completionHandler(nil)
            return
        }

        let activationState = sourceWebView.popupUserActivation.claim(
            webKitUserInitiated: nil
        )
        let request = SumiFilePickerPermissionRequest(
            parameters: parameters,
            frame: frame,
            userActivation: activationState
        )
        let currentPageID: @MainActor () -> String? = {
            [weak self, weak webView, weak session] in
            guard let self, let webView, let session,
                  self.currentSession(for: webView) === session
            else { return nil }
            return session.tab.currentPermissionPageId()
        }
        let exactSessionCompletion: @MainActor @Sendable ([URL]?) -> Void = {
            [weak self, weak webView, weak session] urls in
            guard let self, let webView, let session,
                  self.currentSession(for: webView) === session
            else {
                completionHandler(nil)
                return
            }
            completionHandler(urls)
        }
        let didHandleOpenPanel = permissions?.handleFilePickerOpenPanel(
            request,
            tabContext: tabContext,
            webView: webView,
            currentPageID: currentPageID,
            completionHandler: exactSessionCompletion
        ) ?? false
        guard didHandleOpenPanel else {
            RuntimeDiagnostics.emit("📁 [AuxiliaryWindowUIDelegate] Denying file picker because permission runtime is unavailable.")
            completionHandler(nil)
            return
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        guard let session = currentSession(for: webView) else {
            completionHandler()
            return
        }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: session.window) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        guard let session = currentSession(for: webView) else {
            completionHandler(false)
            return
        }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: session.window) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        guard let session = currentSession(for: webView) else {
            completionHandler(nil)
            return
        }
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input
        alert.beginSheetModal(for: session.window) { response in
            completionHandler(
                response == .alertFirstButtonReturn ? input.stringValue : nil
            )
        }
    }

    private func currentSession(
        for webView: WKWebView
    ) -> AuxiliaryWindowSession? {
        guard let sessions,
              let sessionReceipt,
              sessionReceipt.webViewIdentity == ObjectIdentifier(webView),
              let session = sessions.session(for: sessionReceipt),
              session.webView === webView
        else { return nil }
        return session
    }
}
