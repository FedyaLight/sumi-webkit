import AppKit
import Foundation
import WebKit

// MARK: - WKUIDelegate
extension Tab: WKUIDelegate {
    nonisolated static func isExtensionOriginatedPopupNavigation(
        sourceURL: URL?,
        requestURL: URL?
    ) -> Bool {
        let extensionSchemes: Set<String> = [
            "webkit-extension",
            "safari-web-extension",
        ]

        let sourceScheme = sourceURL?.scheme?.lowercased()
        let requestScheme = requestURL?.scheme?.lowercased()
        return extensionSchemes.contains(sourceScheme ?? "")
            || extensionSchemes.contains(requestScheme ?? "")
    }

    nonisolated static func isExtensionOriginatedExternalPopupNavigation(
        sourceURL: URL?,
        requestURL: URL?
    ) -> Bool {
        let extensionSchemes: Set<String> = [
            "webkit-extension",
            "safari-web-extension",
        ]
        let sourceScheme = sourceURL?.scheme?.lowercased()
        let requestScheme = requestURL?.scheme?.lowercased()

        return extensionSchemes.contains(sourceScheme ?? "")
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
            completionHandler(
                self.navigationDelegateBundle(for: webView)?.popupHandling.createWebView(
                    from: webView,
                    with: configuration,
                    for: navigationAction,
                    windowFeatures: windowFeatures
                )
            )
        }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
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
        completionHandler: @escaping (Bool) -> Void
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
        completionHandler: @escaping (String?) -> Void
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
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        openPanel.canChooseDirectories = parameters.allowsDirectories
        openPanel.canChooseFiles = true
        openPanel.resolvesAliases = true
        openPanel.title = "Choose File"
        openPanel.prompt = "Choose"

        DispatchQueue.main.async {
            if let window = webView.window {
                openPanel.beginSheetModal(for: window) { response in
                    RuntimeDiagnostics.emit("📁 [Tab] Open panel sheet completed with response: \(response)")
                    if response == .OK {
                        RuntimeDiagnostics.emit(
                            "📁 [Tab] User selected files: \(openPanel.urls.map { $0.lastPathComponent })"
                        )
                        completionHandler(openPanel.urls)
                    } else {
                        RuntimeDiagnostics.emit("📁 [Tab] User cancelled file selection")
                        completionHandler(nil)
                    }
                }
            } else {
                openPanel.begin { response in
                    RuntimeDiagnostics.emit("📁 [Tab] Open panel modal completed with response: \(response)")
                    if response == .OK {
                        RuntimeDiagnostics.emit(
                            "📁 [Tab] User selected files: \(openPanel.urls.map { $0.lastPathComponent })"
                        )
                        completionHandler(openPanel.urls)
                    } else {
                        RuntimeDiagnostics.emit("📁 [Tab] User cancelled file selection")
                        completionHandler(nil)
                    }
                }
            }
        }
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
        RuntimeDiagnostics.emit(
            "🔐 [Tab] Media capture authorization requested for type: \(type.rawValue) from origin: \(origin)"
        )
        decisionHandler(.grant)
    }
}
