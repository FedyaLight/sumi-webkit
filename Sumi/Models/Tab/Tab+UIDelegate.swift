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
        guard let bm = browserManager else { return nil }
        let navigationFlags = navigationModifierFlags(from: navigationAction)
        let isExtensionOriginated = Self.isExtensionOriginatedPopupNavigation(
            sourceURL: navigationAction.sourceFrame.request.url,
            requestURL: navigationAction.request.url
        )

        if let url = navigationAction.request.url,
           Self.isExtensionOriginatedExternalPopupNavigation(
                sourceURL: navigationAction.sourceFrame.request.url,
                requestURL: url
           ),
           bm.extensionManager.consumeRecentlyOpenedExtensionTabRequest(for: url)
        {
            return nil
        }

        if let url = navigationAction.request.url,
           isExtensionOriginated == false,
           isGlanceTriggerActive(navigationFlags)
        {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.openURLInGlance(url)
            }
            return nil
        }

        if let url = navigationAction.request.url,
           isExtensionOriginated == false,
           shouldRedirectToPeek(url: url)
        {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.openURLInGlance(url)
            }

            return nil
        }

        bm.extensionManager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            reason: "Tab.createPopupWebView.configuration"
        )
        let newWebView = FocusableWKWebView(frame: .zero, configuration: configuration)
        let newTab = bm.createPopupTab(
            from: self,
            webViewConfigurationOverride: configuration,
            activate: true
        )

        newWebView.navigationDelegate = newTab
        newWebView.uiDelegate = newTab
        newWebView.allowsBackForwardNavigationGestures = true
        newWebView.allowsMagnification = true
        newWebView.owningTab = newTab

        newTab.adoptPopupWebView(newWebView)
        if isExtensionOriginated {
            bm.extensionManager.prepareWebViewForExtensionRuntime(
                newWebView,
                currentURL: navigationAction.request.url,
                reason: "Tab.createPopupWebView"
            )
        }

        SumiUserAgent.apply(to: newWebView)

        newWebView.configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        newWebView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        if let url = navigationAction.request.url,
           url.scheme != nil,
           url.absoluteString != "about:blank"
        {
            newTab.loadURL(url)
        }

        return newWebView
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

    @available(macOS 10.15, *)
    public func webView(
        _ webView: WKWebView,
        enterFullScreenForVideoWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        RuntimeDiagnostics.emit("🎬 [Tab] Entering full-screen for video - delegate method called!")

        guard let window = webView.window else {
            RuntimeDiagnostics.emit("❌ [Tab] No window found for full-screen")
            completionHandler(
                false,
                NSError(
                    domain: "Tab",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No window available for full-screen"]
                )
            )
            return
        }

        RuntimeDiagnostics.emit("🎬 [Tab] Found window: \(window), entering full-screen...")
        DispatchQueue.main.async {
            window.toggleFullScreen(nil)
            RuntimeDiagnostics.emit("🎬 [Tab] Full-screen toggle called")
        }
        completionHandler(true, nil)
    }

    @available(macOS 10.15, *)
    public func webView(
        _ webView: WKWebView,
        exitFullScreenWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        RuntimeDiagnostics.emit("🎬 [Tab] Exiting full-screen for video - delegate method called!")

        guard let window = webView.window else {
            RuntimeDiagnostics.emit("❌ [Tab] No window found for exiting full-screen")
            completionHandler(
                false,
                NSError(
                    domain: "Tab",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No window available for exiting full-screen"]
                )
            )
            return
        }

        RuntimeDiagnostics.emit("🎬 [Tab] Found window: \(window), exiting full-screen...")
        DispatchQueue.main.async {
            window.toggleFullScreen(nil)
            RuntimeDiagnostics.emit("🎬 [Tab] Full-screen exit toggle called")
        }
        completionHandler(true, nil)
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
