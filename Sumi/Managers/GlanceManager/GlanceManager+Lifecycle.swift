@MainActor
extension GlanceManager {
    func moveToSplitView() {
        guard let session = currentSession,
              let runtime,
              let windowState = targetWindowState(for: session)
        else { return }

        transition(to: .promoting)
        let newTab = promotePreviewTab(for: session, runtime: runtime, windowState: windowState)
        runtime.selectPromotedTab(newTab, windowState)
        runtime.createSplitPlaceholder(windowState)
        finishPromotedSession()
    }

    func moveToNewTab(finishesAfterDisplayUpdate: Bool = false) {
        guard let session = currentSession,
              let runtime else { return }

        transition(to: .promoting)
        let windowState = targetWindowState(for: session)
        let newTab = promotePreviewTab(
            for: session,
            runtime: runtime,
            windowState: windowState
        )

        if let windowState {
            runtime.selectPromotedTab(newTab, windowState)
        } else {
            runtime.selectPromotedTabInActiveWindow(newTab)
        }
        if finishesAfterDisplayUpdate {
            beginPromotedSessionAttachmentWait(sessionID: session.id)
        } else {
            finishPromotedSession()
        }
    }

    private func promotePreviewTab(
        for session: GlanceSession,
        runtime: Runtime,
        windowState: BrowserWindowState?
    ) -> Tab {
        materializePreviewWebViewIfNeeded(for: session)
        return runtime.adoptPreviewTab(
            session.previewTab,
            session.sourceTab,
            windowState
        )
    }

    private func targetWindowState(for session: GlanceSession) -> BrowserWindowState? {
        windowRegistry?.windows[session.windowId]
            ?? session.sourceTab.flatMap { runtime?.windowStateContainingTab($0) }
            ?? windowRegistry?.activeWindow
    }

    private func finishPromotedSession() {
        currentSession = nil
        transition(to: .idle)
    }

    func finishPromotedSession(sessionID: UUID) {
        guard currentSession?.id == sessionID else { return }
        completePromotedSessionAttachment(sessionID: sessionID)
        finishPromotedSession()
    }

    private func materializePreviewWebViewIfNeeded(for session: GlanceSession) {
        guard let webView = session.previewTab.ensureWebView() else { return }
        webView.allowsMagnification = false
        session.observe(webView)
    }
}
