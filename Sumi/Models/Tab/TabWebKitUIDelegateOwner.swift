import AppKit
import Foundation
import WebKit

@MainActor
final class TabWebKitUIDelegateOwner: NSObject, WKUIDelegate {
    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
        super.init()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        tab?.navigationDelegateBundle(for: webView)?.createWebView(
            from: webView,
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
        guard let tab else {
            completionHandler(nil)
            return
        }

        tab.dispatchCreateWebView(from: webView) { [weak tab, weak webView] in
            guard let tab, let webView else {
                completionHandler(nil)
                return
            }
            Task { @MainActor in
                let popupWebView = await tab.navigationDelegateBundle(for: webView)?.createWebViewAsync(
                    from: webView,
                    with: configuration,
                    for: navigationAction,
                    windowFeatures: windowFeatures
                )
                completionHandler(popupWebView)
            }
        }
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let tab else { return }
        RuntimeDiagnostics.debug(category: "Tab") {
            "WebKit requested WebView close for tab=\(tab.id.uuidString.prefix(8))."
        }

        if tab.webKitUIRuntime.handleWebViewDidClose(webView) {
            return
        }

        tab.cleanupCloneWebView(webView)
        tab.clearCurrentWebViewOwnershipIfIdentical(to: webView)
    }

    func webView(
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

    func webView(
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

    func webView(
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

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        guard let tab else {
            completionHandler(nil)
            return
        }
        tab.webKitPermissionUIDelegateOwner.runOpenPanel(
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
        tab?.webKitUIRuntime.saveDownloadedData(
            data,
            suggestedFilename.isEmpty ? (webView.url?.lastPathComponent ?? "download") : suggestedFilename,
            mimeType,
            originatingURL
        )
    }

    @available(macOS 13.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCaptureAuthorization type: WKMediaCaptureType,
        for origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        guard let tab else {
            decisionHandler(.deny)
            return
        }
        tab.webKitPermissionUIDelegateOwner.requestMediaCaptureAuthorization(
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
        guard let tab else {
            decisionHandler(SumiWebKitDisplayCapturePermissionDecision.deny.rawValue)
            return
        }
        tab.webKitPermissionUIDelegateOwner.requestDisplayCapturePermission(
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
        guard let tab else {
            decisionHandler(false)
            return
        }
        tab.webKitPermissionUIDelegateOwner.requestUserMediaAuthorization(
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
        guard let tab else {
            completionHandler(false)
            return
        }
        tab.webKitPermissionUIDelegateOwner.requestStorageAccessPanel(
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
        guard let tab else {
            completionHandler(false)
            return
        }
        tab.webKitPermissionUIDelegateOwner.requestStorageAccessPanel(
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
        guard let tab else {
            decisionHandler(false)
            return
        }
        tab.webKitPermissionUIDelegateOwner.requestLegacyGeolocationPermission(
            webView,
            frame: frame,
            decisionHandler: decisionHandler
        )
    }

    @available(macOS 27.0, *)
    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        guard let tab else {
            decisionHandler(.deny)
            return
        }
        tab.webKitPermissionUIDelegateOwner.requestGeolocationPermission(
            webView,
            origin: origin,
            initiatedByFrame: frame,
            decisionHandler: decisionHandler
        )
    }
}
