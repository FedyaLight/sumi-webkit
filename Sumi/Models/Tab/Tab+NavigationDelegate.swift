import AppKit
import Foundation
import WebKit

// MARK: - WKNavigationDelegate
extension Tab: WKNavigationDelegate {

    // MARK: - Loading Start
    public func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        browserManager?.findManager.closeForNavigation(tab: self)
        loadingState = .didStartProvisionalNavigation
        browserManager?.extensionManager.notifyTabPropertiesChanged(
            self,
            properties: [.loading]
        )

        if let newURL = webView.url {
            if newURL.absoluteString != self.url.absoluteString {
                resetPlaybackActivity()
                self.url = newURL
            } else {
                self.url = newURL
            }
        }
    }

    // MARK: - Content Committed
    public func webView(
        _ webView: WKWebView,
        didCommit navigation: WKNavigation!
    ) {
        loadingState = .didCommit
        browserManager?.extensionManager.notifyTabPropertiesChanged(
            self,
            properties: [.loading]
        )

        if let newURL = webView.url {
            self.url = newURL
            noteCommittedMainDocumentNavigation(to: newURL)
            historyRecorder.didCommitMainFrameNavigation(
                to: newURL,
                kind: pendingMainFrameNavigationKind == .backForward ? .backForward : .regular,
                tab: self
            )
            browserManager?.extensionManager.markTabEligibleAfterCommittedNavigation(
                self,
                reason: "Tab.didCommitMainDocumentNavigation"
            )
            if pendingMainFrameNavigationKind != .backForward {
                browserManager?.syncTabAcrossWindows(
                    self.id,
                    originatingWebView: webView
                )
            }
            browserManager?.extensionManager.notifyTabPropertiesChanged(
                self,
                properties: [.URL, .loading]
            )
        }
        NotificationCenter.default.post(
            name: .sumiTabNavigationStateDidChange,
            object: self,
            userInfo: ["tabId": id]
        )
    }

    // MARK: - Loading Success
    public func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        loadingState = .didFinish
        browserManager?.extensionManager.notifyTabPropertiesChanged(
            self,
            properties: [.loading]
        )

        if let newURL = webView.url {
            self.url = newURL
            browserManager?.loadZoomForTab(self.id)
        }

        updateNavigationState()
        let resolvedTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if webView.url != nil {
            historyRecorder.updateTitle(resolvedTitle, tab: self)
        }
        browserManager?.tabManager.scheduleRuntimeStatePersistence(for: self)
        if pendingMainFrameNavigationKind == .backForward {
            finishBackForwardNavigationTracking(using: webView)
            browserManager?.syncTabAcrossWindows(
                self.id,
                originatingWebView: webView
            )
        } else {
            pendingMainFrameNavigationKind = nil
        }

        if let currentURL = webView.url {
            Task { @MainActor in
                await self.fetchAndSetFavicon(for: currentURL)
            }
        }

        injectLinkHoverJavaScript(to: webView)
        if let currentURL = webView.url {
            browserManager?.sumiScriptsManager.injectDocumentIdleScripts(for: webView, url: currentURL)
        }

        if audioState.isMuted {
            setMuted(true)
        }

        SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
    }

    // MARK: - Same Document Navigation (WebKit `WKNavigationDelegatePrivate`)
    /// WebKit invokes this private selector with `_WKSameDocumentNavigationType` as `NSInteger`.
    @objc(_webView:navigation:didSameDocumentNavigation:)
    func webView(
        _ webView: WKWebView,
        navigation: WKNavigation!,
        didSameDocumentNavigation navigationTypeRaw: Int
    ) {
        guard let newURL = webView.url else { return }

        handleSameDocumentNavigation(to: newURL)
        historyRecorder.didSameDocumentNavigation(
            to: newURL,
            type: SumiSameDocumentNavigationType(rawValue: navigationTypeRaw),
            tab: self
        )
        if pendingMainFrameNavigationKind == .backForward {
            scheduleBackForwardSameDocumentSettle(using: webView)
        } else {
            browserManager?.tabManager.scheduleRuntimeStatePersistence(for: self)
            browserManager?.syncTabAcrossWindows(
                self.id,
                originatingWebView: webView
            )
            pendingMainFrameNavigationKind = nil
        }

        if SumiSameDocumentNavigationType.shouldCloseFindInPage(forWebKitSameDocumentNavigationRaw: navigationTypeRaw) {
            browserManager?.findManager.closeForSameDocumentNavigation(tab: self)
        }

        browserManager?.extensionManager.notifyTabPropertiesChanged(
            self,
            properties: [.URL]
        )
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        loadingState = .didFail(error)
        finishBackForwardNavigationTracking(using: webView)
        updateNavigationState()
        browserManager?.extensionManager.notifyTabPropertiesChanged(
            self,
            properties: [.loading]
        )
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        loadingState = .didFailProvisionalNavigation(error)
        finishBackForwardNavigationTracking(using: webView)
        updateNavigationState()
        browserManager?.extensionManager.notifyTabPropertiesChanged(
            self,
            properties: [.loading]
        )
    }

    public func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let handled = browserManager?.authenticationManager.handleAuthenticationChallenge(
            challenge,
            for: self,
            completionHandler: completionHandler
        ), handled {
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrameNavigation = navigationAction.targetFrame?.isMainFrame == true
        if isMainFrameNavigation {
            if navigationAction.navigationType == .backForward {
                beginBackForwardNavigationTracking(on: webView)
            } else {
                markRegularMainFrameNavigation(on: webView)
            }
        }

        if let url = navigationAction.request.url,
           isMainFrameNavigation
        {
            if browserManager?.sumiScriptsManager.interceptInstallNavigationIfNeeded(url) == true {
                decisionHandler(.cancel)
                return
            }
            browserManager?.extensionManager.prepareWebViewForExtensionRuntime(
                webView,
                currentURL: url,
                reason: "Tab.decidePolicyForNavigationAction"
            )
            browserManager?.sumiScriptsManager.installContentController(
                webView.configuration.userContentController,
                for: url,
                webViewId: id,
                profileId: resolveProfile()?.id ?? profileId,
                isEphemeral: isEphemeral
            )
        }

        let navigationFlags = navigationModifierFlags(from: navigationAction)

        if let url = navigationAction.request.url,
           navigationAction.navigationType == .linkActivated,
           isGlanceTriggerActive(navigationFlags)
        {
            decisionHandler(.cancel)
            RunLoop.current.perform { [weak self] in
                Task { @MainActor [weak self] in
                    self?.openURLInGlance(url)
                }
            }
            return
        }

        if #available(macOS 12.3, *), navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        decisionHandler(.allow)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame,
           let url = navigationResponse.response.url,
           browserManager?.sumiScriptsManager.interceptInstallNavigationIfNeeded(url) == true
        {
            decisionHandler(.cancel)
            return
        }

        if let response = navigationResponse.response as? HTTPURLResponse,
           let disposition = response.allHeaderFields["Content-Disposition"] as? String,
           disposition.lowercased().contains("attachment")
        {
            decisionHandler(.download)
            return
        }

        if navigationResponse.isForMainFrame && !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }

        decisionHandler(.allow)
    }

    public func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        let originalURL = navigationAction.request.url ?? URL(string: "https://example.com")!
        let suggestedFilename = DownloadFileUtilities.suggestedFilename(
            response: nil,
            requestURL: navigationAction.request.url,
            fallback: "download"
        )

        RuntimeDiagnostics.emit("🔽 [Tab] Download started from navigationAction: \(originalURL.absoluteString)")
        RuntimeDiagnostics.emit("🔽 [Tab] Suggested filename: \(suggestedFilename)")
        RuntimeDiagnostics.emit("🔽 [Tab] BrowserManager available: \(browserManager != nil)")

        _ = browserManager?.downloadManager.addDownload(
            download,
            originalURL: originalURL,
            websiteURL: webView.url,
            suggestedFilename: suggestedFilename,
            flyAnimationOriginalRect: fileIconFlyAnimationOriginalRect(in: webView)
        )
    }

    public func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        let originalURL = navigationResponse.response.url ?? URL(string: "https://example.com")!
        let suggestedFilename = DownloadFileUtilities.suggestedFilename(
            response: navigationResponse.response,
            requestURL: navigationResponse.response.url,
            fallback: "download"
        )

        RuntimeDiagnostics.emit("🔽 [Tab] Download started from navigationResponse: \(originalURL.absoluteString)")
        RuntimeDiagnostics.emit("🔽 [Tab] Suggested filename: \(suggestedFilename)")
        RuntimeDiagnostics.emit("🔽 [Tab] BrowserManager available: \(browserManager != nil)")

        _ = browserManager?.downloadManager.addDownload(
            download,
            originalURL: originalURL,
            websiteURL: webView.url,
            suggestedFilename: suggestedFilename,
            flyAnimationOriginalRect: fileIconFlyAnimationOriginalRect(in: webView)
        )
    }

    private func fileIconFlyAnimationOriginalRect(in webView: WKWebView) -> NSRect? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let window = webView.window,
              let dockScreen = NSScreen.dockScreen
        else { return nil }

        let size = webView.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let sourceRect = NSRect(
            x: size.width / 2 - 32,
            y: size.height / 2 - 32,
            width: 64,
            height: 64
        )
        let windowRect = webView.convert(sourceRect, to: nil)
        let globalRect = window.convertToScreen(windowRect)
        return dockScreen.convertFromGlobalScreenCoordinates(globalRect)
    }
}
