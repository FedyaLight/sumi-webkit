import AppKit
import Foundation
import WebKit

// MARK: - WKUIDelegate
extension Tab: WKUIDelegate {
    nonisolated static func isExtensionOriginatedPopupNavigation(
        sourceURL: URL?,
        requestURL: URL?
    ) -> Bool {
        ExtensionUtils.isExtensionOwnedURL(sourceURL)
            || ExtensionUtils.isExtensionOwnedURL(requestURL)
    }

    nonisolated static func isExtensionOriginatedExternalPopupNavigation(
        sourceURL: URL?,
        requestURL: URL?
    ) -> Bool {
        let requestScheme = requestURL?.scheme?.lowercased()

        return ExtensionUtils.isExtensionOwnedURL(sourceURL)
            && (requestScheme == "http" || requestScheme == "https")
    }

    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        navigationDelegateBundle(for: webView)?.popupHandling.createWebView(
            from: webView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures
        )
    }

    @MainActor
    @objc(_webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:completionHandler:)
    func webView(
        _ webView: WKWebView,
        createWebViewWithConfiguration configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures,
        completionHandler: @escaping (WKWebView?) -> Void
    ) {
        dispatchCreateWebView(from: webView) { [weak self, weak webView] in
            guard let self, let webView else {
                completionHandler(nil)
                return
            }
            Task { @MainActor in
                let popupWebView = await self.navigationDelegateBundle(for: webView)?.popupHandling.createWebViewAsync(
                    from: webView,
                    with: configuration,
                    for: navigationAction,
                    windowFeatures: windowFeatures
                )
                completionHandler(popupWebView)
            }
        }
    }

    public func webViewDidClose(_ webView: WKWebView) {
        RuntimeDiagnostics.debug(category: "Tab") {
            "WebKit requested WebView close for tab=\(id.uuidString.prefix(8))."
        }

        if browserManager?.handleWebViewDidClose(webView) == true {
            return
        }

        cleanupCloneWebView(webView)
        clearCurrentWebViewOwnershipIfIdentical(to: webView)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "JavaScript Alert"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if let window = webView.window {
            alert.beginSheetModal(for: window) { _ in
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "JavaScript Confirm"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if let window = webView.window {
            alert.beginSheetModal(for: window) { result in
                completionHandler(result == .alertFirstButtonReturn)
            }
        } else {
            completionHandler(false)
        }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "JavaScript Prompt"
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.allowsWritingTools = false
        textField.stringValue = defaultText ?? ""
        alert.accessoryView = textField

        if let window = webView.window {
            alert.beginSheetModal(for: window) { result in
                completionHandler(result == .alertFirstButtonReturn ? textField.stringValue : nil)
            }
        } else {
            completionHandler(nil)
        }
    }

    public func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        webKitPermissionUIDelegateOwner.runOpenPanel(
            webView,
            parameters: parameters,
            initiatedByFrame: frame,
            completionHandler: completionHandler
        )
    }

    /// WebKit private save-data hook used by "Save Page As..." style paths when available.
    @objc(_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:)
    func webView(
        _ webView: WKWebView,
        saveDataToFile data: Data,
        suggestedFilename: String,
        mimeType: String?,
        originatingURL: URL
    ) {
        browserManager?.downloadManager.saveDownloadedData(
            data,
            suggestedFilename: suggestedFilename.isEmpty ? (webView.url?.lastPathComponent ?? "download") : suggestedFilename,
            mimeType: mimeType,
            originatingURL: originatingURL
        )
    }

    @available(macOS 13.0, *)
    public func webView(
        _ webView: WKWebView,
        requestMediaCaptureAuthorization type: WKMediaCaptureType,
        for origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        webKitPermissionUIDelegateOwner.requestMediaCaptureAuthorization(
            webView,
            type: type,
            origin: origin,
            initiatedByFrame: frame,
            decisionHandler: decisionHandler
        )
    }

    @objc(_webView:requestDisplayCapturePermissionForOrigin:initiatedByFrame:withSystemAudio:decisionHandler:)
    func _webView(
        _ webView: WKWebView,
        requestDisplayCapturePermissionForOrigin origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        withSystemAudio _: Bool,
        decisionHandler: @escaping (Int) -> Void
    ) {
        webKitPermissionUIDelegateOwner.requestDisplayCapturePermission(
            webView,
            origin: origin,
            initiatedByFrame: frame,
            decisionHandler: decisionHandler
        )
    }

    @objc(_webView:requestUserMediaAuthorizationForDevices:url:mainFrameURL:decisionHandler:)
    func webView(
        _ webView: WKWebView,
        requestUserMediaAuthorizationForDevices devicesRawValue: UInt,
        url requestURL: URL,
        mainFrameURL: URL,
        decisionHandler: @escaping (Bool) -> Void
    ) {
        webKitPermissionUIDelegateOwner.requestUserMediaAuthorization(
            webView,
            devicesRawValue: devicesRawValue,
            requestURL: requestURL,
            mainFrameURL: mainFrameURL,
            decisionHandler: decisionHandler
        )
    }

    @available(macOS 10.14, *)
    @objc(_webView:requestStorageAccessPanelForDomain:underCurrentDomain:completionHandler:)
    func webView(
        _ webView: WKWebView,
        requestStorageAccessPanelForDomain requestingDomain: String,
        underCurrentDomain currentDomain: String,
        completionHandler: @escaping (Bool) -> Void
    ) {
        webKitPermissionUIDelegateOwner.requestStorageAccessPanel(
            webView,
            requestingDomain: requestingDomain,
            currentDomain: currentDomain,
            completionHandler: completionHandler
        )
    }

    @available(macOS 15.0, *)
    @objc(_webView:requestStorageAccessPanelForDomain:underCurrentDomain:forQuirkDomains:completionHandler:)
    func webView(
        _ webView: WKWebView,
        requestStorageAccessPanelForDomain requestingDomain: String,
        underCurrentDomain currentDomain: String,
        forQuirkDomains quirkDomains: [String: [String]],
        completionHandler: @escaping (Bool) -> Void
    ) {
        webKitPermissionUIDelegateOwner.requestStorageAccessPanel(
            webView,
            requestingDomain: requestingDomain,
            currentDomain: currentDomain,
            quirkDomains: quirkDomains,
            completionHandler: completionHandler
        )
    }

    @objc(_webView:requestGeolocationPermissionForFrame:decisionHandler:)
    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor frame: WKFrameInfo,
        decisionHandler: @escaping (Bool) -> Void
    ) {
        webKitPermissionUIDelegateOwner.requestLegacyGeolocationPermission(
            webView,
            frame: frame,
            decisionHandler: decisionHandler
        )
    }

    @available(macOS 27.0, *)
    public func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        webKitPermissionUIDelegateOwner.requestGeolocationPermission(
            webView,
            origin: origin,
            initiatedByFrame: frame,
            decisionHandler: decisionHandler
        )
    }
}
