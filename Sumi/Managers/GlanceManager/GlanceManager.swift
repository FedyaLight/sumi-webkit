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

enum GlancePresentationPhase: Equatable {
    case idle
    case opening
    case open
    case closing
    case promoting
}

@MainActor
final class GlanceManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var phase: GlancePresentationPhase = .idle
    @Published var currentSession: GlanceSession?

    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func presentExternalURL(_ url: URL, from tab: Tab?) {
        guard let browserManager else { return }

        if currentSession?.currentURL == url {
            return
        }

        if currentSession != nil {
            finishCurrentSession(reason: .close, preservesPreviewWebView: false)
        }

        let windowState = tab.flatMap { browserManager.windowState(containing: $0) } ?? windowRegistry?.activeWindow
        let windowId = windowState?.id ?? UUID()
        let previewTab = makePreviewTab(for: url, sourceTab: tab)

        let originRect = tab?.glanceOriginRectInWindow()
            ?? GlanceManager.fallbackOriginRect(in: windowState?.window)

        let session = GlanceSession(
            targetURL: url,
            windowId: windowId,
            sourceTab: tab,
            previewTab: previewTab,
            originRectInWindow: originRect
        )

        currentSession = session
        transition(to: .opening)
        NotificationCenter.default.post(name: .glanceDidActivate, object: self)

        Task { @MainActor [weak self, weak session] in
            guard let self,
                  let session,
                  self.currentSession?.id == session.id,
                  let webView = previewTab.ensureWebView()
            else { return }

            webView.allowsMagnification = false
            session.observe(webView)
            self.currentSession = session
        }
    }

    var canEnterSplitView: Bool {
        guard let browserManager,
              let windowId = currentSession?.windowId else { return false }

        return !browserManager.splitManager.isSplit(for: windowId)
    }

    func markOpened(sessionID: UUID) {
        guard currentSession?.id == sessionID,
              phase == .opening
        else { return }
        transition(to: .open)
    }

    @discardableResult
    func beginAnimatedDismissal(reason: GlanceDismissReason = .close) -> GlanceSession? {
        guard let currentSession,
              phase != .closing,
              phase != .promoting
        else { return nil }
        transition(to: .closing)
        return currentSession
    }

    func finishAnimatedDismissal(sessionID: UUID, reason: GlanceDismissReason = .close) {
        guard currentSession?.id == sessionID else { return }
        finishCurrentSession(reason: reason, preservesPreviewWebView: false)
    }

    func dismissGlance(reason: GlanceDismissReason = .close) {
        guard currentSession != nil || isActive else { return }
        transition(to: .closing)
        finishCurrentSession(reason: reason, preservesPreviewWebView: false)
    }

    func adoptedPreviewTabForTesting() -> Tab? {
        currentSession?.previewTab
    }

    func transition(to newPhase: GlancePresentationPhase) {
        phase = newPhase
        isActive = newPhase != .idle
    }

    private func finishCurrentSession(
        reason: GlanceDismissReason,
        preservesPreviewWebView: Bool
    ) {
        guard let session = currentSession else {
            transition(to: .idle)
            return
        }

        if !preservesPreviewWebView,
           let webView = session.previewTab.existingWebView {
            session.previewTab.cleanupCloneWebView(webView)
            session.previewTab._webView = nil
            session.previewTab.primaryWindowId = nil
        }

        currentSession = nil
        transition(to: .idle)
        NotificationCenter.default.post(name: .glanceDidDeactivate, object: self)
    }

    private func makePreviewTab(for url: URL, sourceTab: Tab?) -> Tab {
        let sourceProfile = sourceTab?.resolveProfile()
        let targetSpace = sourceTab?.spaceId.flatMap { spaceId in
            browserManager?.tabManager.spaces.first(where: { $0.id == spaceId })
        } ?? browserManager?.tabManager.currentSpace

        let tab = Tab(
            url: url,
            name: url.host ?? "Glance",
            favicon: "globe",
            spaceId: targetSpace?.id,
            index: 0,
            browserManager: browserManager
        )
        tab.sumiSettings = browserManager?.sumiSettings
        tab.profileId = sourceProfile?.id ?? targetSpace?.profileId ?? browserManager?.currentProfile?.id
        return tab
    }

    private static func fallbackOriginRect(in window: NSWindow?) -> CGRect {
        let point = window?.mouseLocationOutsideOfEventStream
            ?? CGPoint(x: (window?.frame.width ?? 800) / 2, y: (window?.frame.height ?? 600) / 2)
        return CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let glanceDidActivate = Notification.Name("GlanceDidActivate")
    static let glanceDidDeactivate = Notification.Name("GlanceDidDeactivate")
}
