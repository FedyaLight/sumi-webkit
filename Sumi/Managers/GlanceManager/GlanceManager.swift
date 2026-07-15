//
//  GlanceManager.swift
//  Sumi
//
//

import AppKit
import SumiDomain
import SumiWebRuntime
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

    weak var windowRegistry: WindowRegistry?
    var runtime: Runtime?
    private var pendingSessionSnapshotsByWindow: [UUID: GlanceSessionSnapshot] = [:]
    private let promotionCompletionOwner = GlancePromotionCompletionOwner()

    var isActive: Bool {
        phase != .idle
    }

    func attach(runtime: Runtime) {
        self.runtime = runtime
    }

    @discardableResult
    func presentExternalURL(
        _ url: URL,
        from tab: Tab?,
        originRectInWindow: CGRect? = nil
    ) -> Bool {
        guard let runtime else { return false }

        let windowState = tab.flatMap { runtime.windowStateContainingTab($0) } ?? windowRegistry?.activeWindow
        return presentExternalURL(
            url,
            from: tab,
            resolvedWindowState: windowState,
            fallbackWindowId: windowState?.id ?? UUID(),
            originRectInWindow: originRectInWindow
        )
    }

    /// Presents from an exact browser-window witness. Browser content commands
    /// use this overload so a Tab shown in multiple windows cannot fall back to
    /// an arbitrary logical-Tab lookup.
    @discardableResult
    func presentExternalURL(
        _ url: URL,
        from tab: Tab,
        in sourceWindow: BrowserWindowState,
        originRectInWindow: CGRect? = nil
    ) -> Bool {
        guard runtime != nil else { return false }
        return presentExternalURL(
            url,
            from: tab,
            resolvedWindowState: sourceWindow,
            fallbackWindowId: sourceWindow.id,
            originRectInWindow: originRectInWindow
        )
    }

    private func presentExternalURL(
        _ url: URL,
        from tab: Tab?,
        resolvedWindowState windowState: BrowserWindowState?,
        fallbackWindowId: UUID,
        originRectInWindow: CGRect?
    ) -> Bool {
        guard runtime != nil else { return false }

        let resolvedOriginRect = originRectInWindow
            ?? GlanceManager.fallbackOriginRect(
                in: windowState.flatMap { windowRegistry?.appKitWindow(for: $0) }
            )

        if let currentSession,
           currentSession.currentURL == url,
           currentSession.windowId == fallbackWindowId,
           currentSession.sourceTab?.id == tab?.id,
           currentSession.originRectInWindow == resolvedOriginRect {
            return true
        }

        return beginSession(
            url,
            sourceTab: tab,
            windowState: windowState,
            fallbackWindowId: fallbackWindowId,
            originRectInWindow: resolvedOriginRect,
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
              let runtime else {
            return
        }

        let sourceTab = restoredSourceTab(for: snapshot, in: windowState, runtime: runtime)
        if snapshot.sourceTabId != nil || snapshot.sourceShortcutPinId != nil,
           sourceTab == nil {
            if !runtime.hasLoadedInitialTabData() {
                return
            }
            pendingSessionSnapshotsByWindow.removeValue(forKey: windowState.id)
            return
        }

        pendingSessionSnapshotsByWindow.removeValue(forKey: windowState.id)
        if let sourceTab,
           runtime.currentTab(windowState)?.id != sourceTab.id {
            runtime.restoreSourceSelection(sourceTab, windowState)
        }
        beginSession(
            snapshot.currentURL ?? snapshot.targetURL,
            sourceTab: sourceTab,
            windowState: windowState,
            fallbackWindowId: windowState.id,
            originRectInWindow: snapshot.originRectInWindow?.cgRect
                ?? GlanceManager.fallbackOriginRect(
                    in: windowState.shellWindow(in: windowRegistry)
                ),
            initialTitle: snapshot.title,
            persistsWindowSession: false
        )
    }

    private func restoredSourceTab(
        for snapshot: GlanceSessionSnapshot,
        in windowState: BrowserWindowState,
        runtime: Runtime
    ) -> Tab? {
        if let pinId = snapshot.sourceShortcutPinId,
           let pin = runtime.shortcutPin(pinId) {
            return runtime.activateShortcutPin(
                pin,
                windowState.id,
                pin.spaceId ?? windowState.currentSpaceId
            )
        }

        guard let sourceTabId = snapshot.sourceTabId else { return nil }
        return runtime.tab(sourceTabId)
    }

    var canEnterSplitView: Bool {
        guard let runtime,
              let windowId = currentSession?.windowId else { return false }

        return runtime.visibleSplitTabCount(windowId) < SplitGroup.maximumMembers
    }

    func dismissFloatingBarIfVisible(in windowId: UUID) -> Bool {
        runtime?.dismissFloatingBarIfVisible(windowId) ?? false
    }

    var isFindBarVisible: Bool {
        runtime?.isFindBarVisible() ?? false
    }

    func hideFindBar() {
        runtime?.hideFindBar()
    }

    func registerPromotedHost(
        _ host: SumiWebViewContainerView,
        for session: GlanceSession,
        attachmentCompletion: @escaping PromotedHostAttachmentCompletion
    ) -> Bool {
        runtime?.registerPromotedHost(
            host,
            session.previewTab.id,
            session.windowId,
            attachmentCompletion
        ) ?? false
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
        guard let session = currentSession,
              runtime?.ownsPreviewWebView(session.previewTab, webView) == true
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

    func activePreviewWebView(for windowState: BrowserWindowState) -> WKWebView? {
        guard let session = activeSession(for: windowState) else { return nil }
        return runtime?.previewWebView(session.previewTab)
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
        return runtime?.currentTab(windowState)?.id == sourceTab.id
    }

    func updateContentFrameInWindowSpace(_ frame: CGRect?, sessionID: UUID) {
        guard currentSession?.id == sessionID else { return }
        currentSession?.updateContentFrameInWindowSpace(frame)
    }

    func transition(to newPhase: GlancePresentationPhase) {
        guard phase != newPhase else { return }
        phase = newPhase
    }

    func beginPromotedSessionAttachmentWait(sessionID: UUID) {
        promotionCompletionOwner.beginAwaitingAttachment(sessionID: sessionID) { [weak self] in
            self?.finishPromotedSession(sessionID: sessionID)
        }
    }

    func completePromotedSessionAttachment(sessionID: UUID) {
        promotionCompletionOwner.completeAttachment(sessionID: sessionID)
    }

    private func finishCurrentSession(
        preservesPreviewWebView: Bool,
        persistsWindowSession: Bool
    ) {
        promotionCompletionOwner.cancel()
        guard let session = currentSession else {
            transition(to: .idle)
            return
        }

        if !preservesPreviewWebView {
            runtime?.releasePreviewWebView(session.previewTab)
        }

        let shouldResetFindManager = runtime?.findCurrentTabId() == session.previewTab.id

        currentSession = nil
        transition(to: .idle)
        if persistsWindowSession {
            persistWindowSession(for: session.windowId)
        }
        if shouldResetFindManager {
            runtime?.hideFindBar()
            runtime?.updateFindManagerCurrentTab()
        }
    }

    @discardableResult
    private func beginSession(
        _ url: URL,
        sourceTab tab: Tab?,
        windowState: BrowserWindowState?,
        fallbackWindowId: UUID,
        originRectInWindow originRect: CGRect,
        initialTitle: String? = nil,
        persistsWindowSession: Bool
    ) -> Bool {
        guard let runtime else { return false }
        promotionCompletionOwner.cancel()
        if currentSession != nil {
            finishCurrentSession(preservesPreviewWebView: false, persistsWindowSession: false)
        }

        guard let previewTab = runtime.makePreviewTab(url, tab, windowState) else {
            return false
        }
        let windowId = windowState?.id ?? fallbackWindowId
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
                  let webView = self.runtime?.ensurePreviewWebView(previewTab, windowId)
            else { return }

            webView.allowsMagnification = false
            session.observe(webView)
            self.currentSession = session
        }
        return true
    }

    private func persistWindowSession(for windowId: UUID) {
        guard let windowState = windowRegistry?.windows[windowId] else { return }
        runtime?.persistWindowSession(windowState)
    }

    private static func fallbackOriginRect(in window: NSWindow?) -> CGRect {
        let point = window?.mouseLocationOutsideOfEventStream
            ?? CGPoint(x: (window?.frame.width ?? 800) / 2, y: (window?.frame.height ?? 600) / 2)
        return CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
    }
}
