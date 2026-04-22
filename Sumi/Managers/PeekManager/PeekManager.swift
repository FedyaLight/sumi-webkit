//
//  PeekManager.swift
//  Sumi
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import SwiftUI
import WebKit
import AppKit

enum PeekDismissReason {
    case close
    case promoteToTab
    case moveToSplit
}

@MainActor
final class PeekManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var currentSession: PeekSession?

    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?
    var webView: PeekWebView?
    var webViewCoordinator: PeekWebView.Coordinator?

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func presentExternalURL(_ url: URL, from tab: Tab?) {
        guard browserManager != nil else { return }

        // Don't show Peek if already showing this URL
        if currentSession?.currentURL == url {
            dismissPeek(reason: .close)
            return
        }

        let windowId = windowRegistry?.activeWindow?.id ?? UUID()
        let session = PeekSession(
            targetURL: url,
            windowId: windowId,
            sourceProfileId: tab?.resolveProfile()?.id
        )

        // Create WebView FIRST, then activate
        currentSession = session
        let peekWebView = createWebView()
        self.webView = peekWebView
        
        // Defer activation to avoid runloop-mode reentrancy from WebKit delegates
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isActive = true
            NotificationCenter.default.post(name: .peekDidActivate, object: self)
        }
    }

    func updateWebView(_ webView: PeekWebView) {
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
    static let peekDidActivate = Notification.Name("PeekDidActivate")
    static let peekDidDeactivate = Notification.Name("PeekDidDeactivate")
}
