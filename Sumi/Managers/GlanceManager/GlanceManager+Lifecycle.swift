import Foundation
import WebKit

@MainActor
extension GlanceManager {
    func moveToSplitView() {
        guard let session = currentSession,
              let browserManager,
              let windowState = windowRegistry?.windows[session.windowId] ?? windowRegistry?.activeWindow
        else { return }

        transition(to: .promoting)
        materializePreviewWebViewIfNeeded(for: session)
        let newTab = browserManager.tabManager.adoptGlanceTab(
            session.previewTab,
            sourceTab: session.sourceTab,
            in: browserManager.tabManager.currentSpace
        )
        browserManager.splitManager.enterSplit(with: newTab, placeOn: .right, in: windowState)
        browserManager.selectTab(newTab, in: windowState)
        finishPromotedSession()
    }

    func moveToNewTab() {
        guard let session = currentSession,
              let browserManager else { return }

        transition(to: .promoting)
        materializePreviewWebViewIfNeeded(for: session)
        let newTab = browserManager.tabManager.adoptGlanceTab(
            session.previewTab,
            sourceTab: session.sourceTab,
            in: browserManager.tabManager.currentSpace
        )

        if let windowState = windowRegistry?.windows[session.windowId] ?? windowRegistry?.activeWindow {
            browserManager.selectTab(newTab, in: windowState)
        } else {
            browserManager.selectTab(newTab)
        }
        finishPromotedSession()
    }

    private func finishPromotedSession() {
        currentSession = nil
        transition(to: .idle)
        NotificationCenter.default.post(name: .glanceDidDeactivate, object: self)
    }

    private func materializePreviewWebViewIfNeeded(for session: GlanceSession) {
        guard let webView = session.previewTab.ensureWebView() else { return }
        webView.allowsMagnification = false
        session.observe(webView)
    }
}
