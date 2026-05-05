//
//  GlanceWebView.swift
//  Sumi
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import SwiftUI
import WebKit

struct GlanceWebView: NSViewRepresentable {
    @ObservedObject var session: GlanceSession
    weak var glanceManager: GlanceManager?

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(session: session)
        // Store coordinator reference for WebView extraction immediately
        glanceManager?.webViewCoordinator = coordinator
        return coordinator
    }

    func makeNSView(context: Context) -> WKWebView {
        // Glance is an auxiliary preview surface. Primary normal tabs use the
        // normal-tab BrowserConfiguration path.
        let configuration: WKWebViewConfiguration
        if let profileId = session.sourceProfileId,
           let profile = glanceManager?.browserManager?.profileManager.profiles.first(where: { $0.id == profileId }) {
            configuration = BrowserConfiguration.shared.auxiliaryWebViewConfiguration(
                for: profile,
                surface: .glance
            )
        } else {
            configuration = BrowserConfiguration.shared.auxiliaryWebViewConfiguration(
                surface: .glance
            )
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = false // Disable zoom for glance

        if RuntimeDiagnostics.isDeveloperInspectionEnabled {
            webView.isInspectable = true
        }

        // Store reference in coordinator for transfer to tabs
        context.coordinator.webView = webView

        context.coordinator.installProgressObservation(on: webView)
        context.coordinator.loadInitialURLIfNeeded(on: webView)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.session = session
        context.coordinator.loadInitialURLIfNeeded(on: nsView)

        // Update reference in coordinator
        context.coordinator.webView = nsView
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var session: GlanceSession
        private var progressObservation: NSKeyValueObservation?
        private var didLoadInitialURL = false
        /// MEMORY LEAK FIX: Use weak reference to avoid retaining the WKWebView
        /// when the glance overlay is dismissed. The view hierarchy holds the strong ref.
        weak var webView: WKWebView?

        init(session: GlanceSession) {
            self.session = session
        }

        deinit {
            progressObservation?.invalidate()
        }

        func installProgressObservation(on webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                guard let progress = change.newValue else { return }
                DispatchQueue.main.async {
                    self?.session.updateProgress(progress)
                }
            }
        }

        func loadInitialURLIfNeeded(on webView: WKWebView) {
            guard didLoadInitialURL == false else { return }
            didLoadInitialURL = true
            let request = URLRequest(url: session.currentURL)
            webView.load(request)
        }

        func detachWebViewForTransfer() -> WKWebView? {
            progressObservation?.invalidate()
            progressObservation = nil

            guard let webView else { return nil }
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.removeFromSuperview()
            self.webView = nil
            return webView
        }

        func tearDownForDismissal() {
            progressObservation?.invalidate()
            progressObservation = nil

            guard let webView else { return }

            webView.evaluateJavaScript(
                """
                document.querySelectorAll('video, audio').forEach(function(el) {
                    try { el.pause(); } catch (e) {}
                    try { el.src = ''; } catch (e) {}
                    try { el.load(); } catch (e) {}
                });
                """
            )
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.removeFromSuperview()
            self.webView = nil
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            session.updateLoading(isLoading: true)
            session.updateNavigationState(url: webView.url, title: nil)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            session.updateLoading(isLoading: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            session.updateLoading(isLoading: false)
            session.updateNavigationState(url: webView.url, title: nil)

            webView.evaluateJavaScript("document.title") { [weak self] result, _ in
                guard let self else { return }
                if let title = result as? String {
                    DispatchQueue.main.async {
                        self.session.updateNavigationState(url: nil, title: title)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            session.updateLoading(isLoading: false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            session.updateLoading(isLoading: false)
        }

        // MARK: - WKUIDelegate

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // Handle external links in glance by opening in new tab
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Let normal navigation proceed within the glance
            decisionHandler(.allow)
        }

        // MARK: - File Upload Support
        // Glance file picking is an auxiliary-surface path. Normal tabs must route
        // file picker requests through SumiFilePickerPermissionBridge.
        func webView(
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


            // Ensure we're on the main thread for UI operations
            DispatchQueue.main.async {
                if let window = webView.window {
                    // Present as sheet if we have a window
                    openPanel.beginSheetModal(for: window) { response in
                        if response == .OK {
                            completionHandler(openPanel.urls)
                        } else {
                            completionHandler(nil)
                        }
                    }
                } else {
                    // Fall back to modal presentation
                    openPanel.begin { response in
                        if response == .OK {
                            completionHandler(openPanel.urls)
                        } else {
                            completionHandler(nil)
                        }
                    }
                }
            }
        }
    }
}
