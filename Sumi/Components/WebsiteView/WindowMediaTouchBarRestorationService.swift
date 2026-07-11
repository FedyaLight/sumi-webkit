import AppKit
import WebKit
import SumiWebRuntime

@MainActor
final class WindowMediaTouchBarRestorationService {
    private let windowID: UUID
    private let windowState: BrowserWindowState
    private let browserContext: any WindowWebContentBrowserContext
    private let hostRegistry: WindowWebContentHostRegistry
    private let mutationGate: WindowWebContentCompositorMutationGate
    private let protectionRuntime: WebViewProtectionRuntime
    private let window: () -> NSWindow?
    private let restoreDisplayedHost: (
        Tab,
        WebViewCompositorContainerRegistration
    ) -> Bool

    init(
        windowID: UUID,
        windowState: BrowserWindowState,
        browserContext: any WindowWebContentBrowserContext,
        hostRegistry: WindowWebContentHostRegistry,
        mutationGate: WindowWebContentCompositorMutationGate,
        protectionRuntime: WebViewProtectionRuntime,
        window: @escaping () -> NSWindow?,
        restoreDisplayedHost: @escaping (
            Tab,
            WebViewCompositorContainerRegistration
        ) -> Bool
    ) {
        self.windowID = windowID
        self.windowState = windowState
        self.browserContext = browserContext
        self.hostRegistry = hostRegistry
        self.mutationGate = mutationGate
        self.protectionRuntime = protectionRuntime
        self.window = window
        self.restoreDisplayedHost = restoreDisplayedHost
    }

    func recover(tabID: UUID?, webView: WKWebView) {
        guard let registration = mutationGate.currentRegistration,
              !protectionRuntime.hasActiveHistorySwipe(in: windowID),
              !webView.sumiIsInFullscreenElementPresentation,
              let window = window(),
              window.isKeyWindow
        else {
            return
        }

        guard let currentTab = browserContext.currentTab(for: windowState),
              tabID == nil || currentTab.id == tabID
        else {
            return
        }

        if hostRegistry.displayedHost(for: currentTab.id) == nil {
            guard restoreDisplayedHost(currentTab, registration),
                  mutationGate.owns(registration)
            else {
                return
            }
        }

        guard let host = hostRegistry.displayedHost(for: currentTab.id),
              host.webView === webView,
              host.window === window,
              webView.window === window,
              webView.superview != nil
        else {
            return
        }
        let focusTarget = host.activePresentationWebView
        guard focusTarget.window === window,
              !focusTarget.isHidden
        else {
            return
        }

        resetTouchBar(
            for: webView,
            restoringFocusTo: focusTarget,
            in: window,
            containerRegistration: registration
        )
    }

    private func resetTouchBar(
        for webView: WKWebView,
        restoringFocusTo focusTarget: NSView,
        in window: NSWindow,
        containerRegistration: WebViewCompositorContainerRegistration
    ) {
        guard mutationGate.owns(containerRegistration) else { return }
        let wasFirstResponder = window.firstResponder === focusTarget
        webView.touchBar = nil
        if wasFirstResponder {
            guard mutationGate.owns(containerRegistration) else { return }
            window.makeFirstResponder(nil)
        }
        guard mutationGate.owns(containerRegistration) else { return }
        window.makeFirstResponder(focusTarget)
        guard mutationGate.owns(containerRegistration) else { return }
        webView.touchBar = nil
    }
}
