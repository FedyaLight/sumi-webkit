//
//  GlanceManager.swift
//  Sumi
//
//

import AppKit
import SwiftUI
import WebKit

enum GlancePresentationPhase: Equatable {
    case idle
    case opening
    case open
    case closing
    case promoting
}

@MainActor
final class GlanceManager: ObservableObject {
    @Published var phase: GlancePresentationPhase = .idle
    @Published var currentSession: GlanceSession?

    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?
    private var pendingSessionSnapshotsByWindow: [UUID: GlanceSessionSnapshot] = [:]

    var isActive: Bool {
        phase != .idle
    }

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func presentExternalURL(
        _ url: URL,
        from tab: Tab?,
        originRectInWindow: CGRect? = nil
    ) {
        guard let browserManager else { return }

        if currentSession?.currentURL == url {
            return
        }

        let windowState = tab.flatMap { browserManager.windowState(containing: $0) } ?? windowRegistry?.activeWindow
        let windowId = windowState?.id ?? UUID()
        beginSession(
            url,
            sourceTab: tab,
            windowId: windowId,
            originRectInWindow: originRectInWindow
                ?? tab?.glanceOriginRectInWindow()
                ?? GlanceManager.fallbackOriginRect(in: windowState?.window),
            persistsWindowSession: true
        )
    }

    func makeSessionSnapshot(for windowState: BrowserWindowState) -> GlanceSessionSnapshot? {
        guard let currentSession,
              currentSession.windowId == windowState.id,
              phase != .idle,
              phase != .closing,
              phase != .promoting
        else {
            return nil
        }

        return GlanceSessionSnapshot(
            targetURL: currentSession.currentURL,
            currentURL: currentSession.currentURL,
            title: currentSession.title,
            sourceTabId: currentSession.sourceTab?.id,
            sourceShortcutPinId: currentSession.sourceTab?.shortcutPinId,
            sourceShortcutPinRole: currentSession.sourceTab?.shortcutPinRole,
            originRectInWindow: GlanceSessionRectSnapshot(currentSession.originRectInWindow)
        )
    }

    func restoreSession(_ snapshot: GlanceSessionSnapshot?, in windowState: BrowserWindowState) {
        guard let snapshot else {
            pendingSessionSnapshotsByWindow.removeValue(forKey: windowState.id)
            if currentSession?.windowId == windowState.id {
                dismissGlance(persistsWindowSession: false)
            }
            return
        }

        pendingSessionSnapshotsByWindow[windowState.id] = snapshot
        restorePendingSessionIfPossible(in: windowState)
    }

    func restorePendingSessionIfPossible(in windowState: BrowserWindowState) {
        guard let snapshot = pendingSessionSnapshotsByWindow[windowState.id],
              let browserManager else {
            return
        }

        let sourceTab = restoredSourceTab(for: snapshot, in: windowState, browserManager: browserManager)
        if snapshot.sourceTabId != nil || snapshot.sourceShortcutPinId != nil,
           sourceTab == nil {
            if !browserManager.tabManager.hasLoadedInitialData {
                return
            }
            pendingSessionSnapshotsByWindow.removeValue(forKey: windowState.id)
            return
        }

        pendingSessionSnapshotsByWindow.removeValue(forKey: windowState.id)
        if let sourceTab,
           browserManager.currentTab(for: windowState)?.id != sourceTab.id {
            browserManager.applyTabSelection(
                sourceTab,
                in: windowState,
                updateSpaceFromTab: true,
                updateTheme: false,
                rememberSelection: false,
                persistSelection: false,
                loadPolicy: .deferred
            )
        }
        beginSession(
            snapshot.currentURL ?? snapshot.targetURL,
            sourceTab: sourceTab,
            windowId: windowState.id,
            originRectInWindow: snapshot.originRectInWindow?.cgRect
                ?? GlanceManager.fallbackOriginRect(in: windowState.window),
            initialTitle: snapshot.title,
            persistsWindowSession: false
        )
    }

    private func restoredSourceTab(
        for snapshot: GlanceSessionSnapshot,
        in windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) -> Tab? {
        if let sourceTabId = snapshot.sourceTabId,
           let sourceTab = browserManager.tabManager.tab(for: sourceTabId) {
            return sourceTab
        }

        guard let pinId = snapshot.sourceShortcutPinId,
              let pin = browserManager.tabManager.shortcutPin(by: pinId)
        else {
            return nil
        }

        return browserManager.tabManager.shortcutLiveTab(for: pinId, in: windowState.id)
            ?? browserManager.tabManager.activateShortcutPin(
                pin,
                in: windowState.id,
                currentSpaceId: pin.spaceId ?? windowState.currentSpaceId
            )
    }

    var canEnterSplitView: Bool {
        guard let browserManager,
              let windowId = currentSession?.windowId else { return false }

        return browserManager.splitManager.visibleTabIds(for: windowId).count < SplitGroup.maximumTabs
    }

    func markOpened(sessionID: UUID) {
        guard currentSession?.id == sessionID,
              phase == .opening
        else { return }
        transition(to: .open)
    }

    @discardableResult
    func beginAnimatedDismissal() -> GlanceSession? {
        guard let currentSession,
              phase != .closing,
              phase != .promoting
        else { return nil }
        transition(to: .closing)
        return currentSession
    }

    func finishAnimatedDismissal(sessionID: UUID) {
        guard currentSession?.id == sessionID else { return }
        finishCurrentSession(preservesPreviewWebView: false, persistsWindowSession: true)
    }

    func dismissGlance(persistsWindowSession: Bool = true) {
        guard currentSession != nil || isActive else { return }
        transition(to: .closing)
        finishCurrentSession(
            preservesPreviewWebView: false,
            persistsWindowSession: persistsWindowSession
        )
    }

    @discardableResult
    func handleWebViewDidClose(_ webView: WKWebView) -> Bool {
        guard currentSession?.previewTab.existingWebView === webView
            || currentSession?.previewTab.assignedWebView === webView
        else {
            return false
        }

        dismissGlance()
        return true
    }

    var isPreviewActive: Bool {
        currentSession != nil && phase != .idle && phase != .closing && phase != .promoting
    }

    func presentedSession(for windowState: BrowserWindowState) -> GlanceSession? {
        guard let currentSession,
              phase != .idle,
              currentSession.windowId == windowState.id
        else { return nil }

        if phase == .promoting {
            return currentSession
        }

        guard isSessionVisibleOnSelectedTab(currentSession, in: windowState) else {
            return nil
        }

        return currentSession
    }

    func activePreviewTab(for windowState: BrowserWindowState) -> Tab? {
        activeSession(for: windowState)?.previewTab
    }

    func activeSession(for windowState: BrowserWindowState) -> GlanceSession? {
        guard isPreviewActive else { return nil }
        return presentedSession(for: windowState)
    }

    func sidebarSession(for windowState: BrowserWindowState) -> GlanceSession? {
        guard isPreviewActive,
              let currentSession,
              currentSession.windowId == windowState.id
        else { return nil }
        return currentSession
    }

    private func isSessionVisibleOnSelectedTab(
        _ session: GlanceSession,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let sourceTab = session.sourceTab else { return true }
        return browserManager?.currentTab(for: windowState)?.id == sourceTab.id
    }

    func updateContentFrameInWindowSpace(_ frame: CGRect?, sessionID: UUID) {
        guard currentSession?.id == sessionID else { return }
        currentSession?.updateContentFrameInWindowSpace(frame)
    }

    func transition(to newPhase: GlancePresentationPhase) {
        guard phase != newPhase else { return }
        phase = newPhase
    }

    private func finishCurrentSession(
        preservesPreviewWebView: Bool,
        persistsWindowSession: Bool
    ) {
        guard let session = currentSession else {
            transition(to: .idle)
            return
        }

        if !preservesPreviewWebView,
           let webView = session.previewTab.existingWebView {
            session.previewTab.cleanupCloneWebView(webView)
            session.previewTab.clearCurrentWebViewOwnership()
        }

        let shouldResetFindManager = browserManager?.findManager.currentTab?.id == session.previewTab.id

        currentSession = nil
        transition(to: .idle)
        if persistsWindowSession {
            persistWindowSession(for: session.windowId)
        }
        if shouldResetFindManager {
            browserManager?.findManager.hideFindBar()
            browserManager?.updateFindManagerCurrentTab()
        }
    }

    private func beginSession(
        _ url: URL,
        sourceTab tab: Tab?,
        windowId: UUID,
        originRectInWindow originRect: CGRect,
        initialTitle: String? = nil,
        persistsWindowSession: Bool
    ) {
        if currentSession != nil {
            finishCurrentSession(preservesPreviewWebView: false, persistsWindowSession: false)
        }

        let previewTab = makePreviewTab(for: url, sourceTab: tab)
        let session = GlanceSession(
            targetURL: url,
            windowId: windowId,
            sourceTab: tab,
            previewTab: previewTab,
            originRectInWindow: originRect
        )
        if let initialTitle, !initialTitle.isEmpty {
            session.updateNavigationState(url: nil, title: initialTitle)
        }

        currentSession = session
        transition(to: .opening)
        if persistsWindowSession {
            persistWindowSession(for: windowId)
        }

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

    private func persistWindowSession(for windowId: UUID) {
        guard let windowState = windowRegistry?.windows[windowId] else { return }
        browserManager?.persistWindowSession(for: windowState)
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
