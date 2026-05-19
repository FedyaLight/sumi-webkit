@MainActor
extension GlanceManager {
    func moveToSplitView() {
        guard let session = currentSession,
              let browserManager,
              let windowState = targetWindowState(for: session)
        else { return }

        transition(to: .promoting)
        let newTab = promotePreviewTab(for: session, browserManager: browserManager, windowState: windowState)
        browserManager.splitManager.enterSplit(with: newTab, placeOn: .right, in: windowState)
        finishPromotedSession()
    }

    func moveToNewTab(finishesAfterDisplayUpdate: Bool = false) {
        guard let session = currentSession,
              let browserManager else { return }

        transition(to: .promoting)
        let windowState = targetWindowState(for: session)
        let newTab = promotePreviewTab(
            for: session,
            browserManager: browserManager,
            windowState: windowState
        )

        if let windowState {
            browserManager.selectTab(newTab, in: windowState)
        } else {
            browserManager.selectTab(newTab)
        }
        if finishesAfterDisplayUpdate {
            DispatchQueue.main.async { [weak self, sessionID = session.id] in
                guard self?.currentSession?.id == sessionID else { return }
                self?.finishPromotedSession()
            }
        } else {
            finishPromotedSession()
        }
    }

    private func promotePreviewTab(
        for session: GlanceSession,
        browserManager: BrowserManager,
        windowState: BrowserWindowState?
    ) -> Tab {
        materializePreviewWebViewIfNeeded(for: session)
        return browserManager.tabManager.adoptGlanceTab(
            session.previewTab,
            sourceTab: session.sourceTab,
            in: targetSpace(for: session, browserManager: browserManager, windowState: windowState)
        )
    }

    private func targetWindowState(for session: GlanceSession) -> BrowserWindowState? {
        windowRegistry?.windows[session.windowId]
            ?? session.sourceTab.flatMap { browserManager?.windowState(containing: $0) }
            ?? windowRegistry?.activeWindow
    }

    private func targetSpace(
        for session: GlanceSession,
        browserManager: BrowserManager,
        windowState: BrowserWindowState?
    ) -> Space? {
        windowState?.currentSpaceId.flatMap { spaceId in
            browserManager.tabManager.spaces.first(where: { $0.id == spaceId })
        }
        ?? session.sourceTab?.spaceId.flatMap { spaceId in
            browserManager.tabManager.spaces.first(where: { $0.id == spaceId })
        }
        ?? browserManager.tabManager.currentSpace
    }

    private func finishPromotedSession() {
        currentSession = nil
        transition(to: .idle)
    }

    private func materializePreviewWebViewIfNeeded(for session: GlanceSession) {
        guard let webView = session.previewTab.ensureWebView() else { return }
        webView.allowsMagnification = false
        session.observe(webView)
    }
}
