//
//  GlanceManager.swift
//  Sumi
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import SwiftUI
import WebKit
import AppKit

enum GlanceDismissReason {
    case close
    case promoteToTab
    case moveToSplit
}

@MainActor
final class GlanceManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var currentSession: GlanceSession?

    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?
    var webView: GlanceWebView?
    var webViewCoordinator: GlanceWebView.Coordinator?

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func presentExternalURL(_ url: URL, from tab: Tab?) {
        guard browserManager != nil else { return }

        // Don't show Glance if already showing this URL
        if currentSession?.currentURL == url {
            dismissGlance(reason: .close)
            return
        }

        let windowId = windowRegistry?.activeWindow?.id ?? UUID()
        let session = GlanceSession(
            targetURL: url,
            windowId: windowId,
            sourceProfileId: tab?.resolveProfile()?.id
        )

        // Create WebView FIRST, then activate
        currentSession = session
        let glanceWebView = createWebView()
        self.webView = glanceWebView
        
        // Defer activation to avoid runloop-mode reentrancy from WebKit delegates
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isActive = true
            NotificationCenter.default.post(name: .glanceDidActivate, object: self)
        }
    }

    func updateWebView(_ webView: GlanceWebView) {
        self.webView = webView
    }

    var canEnterSplitView: Bool {
        guard let browserManager,
              let windowId = currentSession?.windowId else { return false }

        return !browserManager.splitManager.isSplit(for: windowId)
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let glanceDidActivate = Notification.Name("GlanceDidActivate")
    static let glanceDidDeactivate = Notification.Name("GlanceDidDeactivate")
}
