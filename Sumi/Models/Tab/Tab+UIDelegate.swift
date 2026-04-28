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
        guard let browserManager,
              let tabContext = filePickerTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit("📁 [Tab] Denying file picker because browser/profile context is unavailable.")
            completionHandler(nil)
            return
        }

        let activationState = popupUserActivationTracker.activationState(webKitUserInitiated: nil)
        let request = SumiFilePickerPermissionRequest(
            parameters: parameters,
            frame: frame,
            userActivation: activationState
        )
        browserManager.filePickerPermissionBridge.handleOpenPanel(
            request,
            tabContext: tabContext,
            webView: webView,
            currentPageId: { [weak self] in self?.currentPermissionPageId() },
            completionHandler: completionHandler
        )
        popupUserActivationTracker.consumeIfUserActivated(activationState)
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
        guard let browserManager,
              let profile = resolveProfile()
        else {
            RuntimeDiagnostics.emit(
                "🔐 [Tab] Denying media capture because browser/profile context is unavailable."
            )
            decisionHandler(.deny)
            return
        }

        let tabId = id.uuidString.lowercased()
        let pageGeneration = String(extensionRuntimeDocumentSequence)
        let committedURL = extensionRuntimeCommittedMainDocumentURL
        let visibleURL = webView.url ?? url
        let mediaRequest = SumiWebKitMediaCaptureRequest(
            mediaType: type,
            origin: origin,
            frame: frame
        )
        let tabContext = SumiWebKitMediaCaptureTabContext(
            tabId: tabId,
            pageId: "\(tabId):\(pageGeneration)",
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: visibleURL,
            mainFrameURL: committedURL ?? webView.url ?? url,
            isActiveTab: isCurrentTab,
            isVisibleTab: primaryWindowId != nil,
            navigationOrPageGeneration: pageGeneration
        )

        browserManager.webKitPermissionBridge.handleMediaCaptureAuthorization(
            mediaRequest,
            tabContext: tabContext,
            webView: webView,
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
        guard let browserManager,
              let tabContext = storageAccessTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit("🍪 [Tab] Denying storage access because browser/profile context is unavailable.")
            completionHandler(false)
            return
        }

        browserManager.storageAccessPermissionBridge.handleStorageAccessRequest(
            SumiStorageAccessRequest(
                requestingDomain: requestingDomain,
                currentDomain: currentDomain
            ),
            tabContext: tabContext,
            webView: webView,
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
        guard let browserManager,
              let tabContext = storageAccessTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit("🍪 [Tab] Denying quirk-domain storage access because browser/profile context is unavailable.")
            completionHandler(false)
            return
        }

        browserManager.storageAccessPermissionBridge.handleStorageAccessRequest(
            SumiStorageAccessRequest(
                requestingDomain: requestingDomain,
                currentDomain: currentDomain,
                quirkDomains: Array(quirkDomains.keys).sorted()
            ),
            tabContext: tabContext,
            webView: webView,
            completionHandler: completionHandler
        )
    }

    @objc(_webView:requestGeolocationPermissionForFrame:decisionHandler:)
    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor frame: WKFrameInfo,
        decisionHandler: @escaping (Bool) -> Void
    ) {
        RuntimeDiagnostics.emit(
            "🔐 [Tab] Legacy geolocation authorization requested from frame: \(String(describing: frame.request.url))"
        )
        guard let browserManager,
              let tabContext = geolocationTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit(
                "🔐 [Tab] Denying geolocation because browser/profile context is unavailable."
            )
            decisionHandler(false)
            return
        }

        browserManager.webKitGeolocationBridge.handleLegacyGeolocationAuthorization(
            SumiWebKitGeolocationRequest(frame: frame),
            tabContext: tabContext,
            webView: webView,
            decisionHandler: decisionHandler
        )
    }

    @available(macOS 12.0, *)
    @objc(_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)
    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        RuntimeDiagnostics.emit(
            "🔐 [Tab] Geolocation authorization requested from origin: \(origin)"
        )
        guard let browserManager,
              let tabContext = geolocationTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit(
                "🔐 [Tab] Denying geolocation because browser/profile context is unavailable."
            )
            decisionHandler(.deny)
            return
        }

        browserManager.webKitGeolocationBridge.handleGeolocationAuthorization(
            SumiWebKitGeolocationRequest(origin: origin, frame: frame),
            tabContext: tabContext,
            webView: webView,
            decisionHandler: decisionHandler
        )
    }

    private func geolocationTabContext(
        for webView: WKWebView
    ) -> SumiWebKitGeolocationTabContext? {
        guard let profile = resolveProfile() else { return nil }

        let tabId = id.uuidString.lowercased()
        let pageGeneration = String(extensionRuntimeDocumentSequence)
        let committedURL = extensionRuntimeCommittedMainDocumentURL
        return SumiWebKitGeolocationTabContext(
            tabId: tabId,
            pageId: "\(tabId):\(pageGeneration)",
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? url,
            mainFrameURL: committedURL ?? webView.url ?? url,
            isActiveTab: isCurrentTab,
            isVisibleTab: primaryWindowId != nil,
            navigationOrPageGeneration: pageGeneration
        )
    }

    private func filePickerTabContext(
        for webView: WKWebView
    ) -> SumiFilePickerPermissionTabContext? {
        guard let profile = resolveProfile() else { return nil }

        let tabId = id.uuidString.lowercased()
        let pageGeneration = String(extensionRuntimeDocumentSequence)
        let committedURL = extensionRuntimeCommittedMainDocumentURL
        return SumiFilePickerPermissionTabContext(
            tabId: tabId,
            pageId: "\(tabId):\(pageGeneration)",
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? url,
            mainFrameURL: committedURL ?? webView.url ?? url,
            isActiveTab: isCurrentTab,
            isVisibleTab: primaryWindowId != nil,
            navigationOrPageGeneration: pageGeneration
        )
    }

    private func storageAccessTabContext(
        for webView: WKWebView
    ) -> SumiStorageAccessTabContext? {
        guard let profile = resolveProfile() else { return nil }

        let tabId = id.uuidString.lowercased()
        let pageGeneration = String(extensionRuntimeDocumentSequence)
        let committedURL = extensionRuntimeCommittedMainDocumentURL
        return SumiStorageAccessTabContext(
            tabId: tabId,
            pageId: "\(tabId):\(pageGeneration)",
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? url,
            mainFrameURL: committedURL ?? webView.url ?? url,
            isActiveTab: isCurrentTab,
            isVisibleTab: primaryWindowId != nil,
            navigationOrPageGeneration: pageGeneration
        )
    }
}
