import Foundation
import WebKit

@MainActor
struct ActivePageResolution {
    enum Source: Equatable {
        case selectedTab
        case glancePreview
    }

    let source: Source
    let windowState: BrowserWindowState
    let tab: Tab
    let url: URL
    let canonicalWebView: WKWebView?

    var presentationWebView: WKWebView? {
        canonicalWebView?.sumiActivePresentationWebView
    }
}

@MainActor
final class ActivePageResolver {
    struct GlanceSnapshot {
        let tab: Tab
        let url: URL
        let webView: WKWebView?
    }

    private let activeWindow: @MainActor () -> BrowserWindowState?
    private let selectedTab: @MainActor (BrowserWindowState) -> Tab?
    private let glanceSnapshot: @MainActor (BrowserWindowState) -> GlanceSnapshot?
    private let windowOwnedWebView: @MainActor (Tab, UUID) -> WKWebView?

    init(
        activeWindow: @escaping @MainActor () -> BrowserWindowState?,
        selectedTab: @escaping @MainActor (BrowserWindowState) -> Tab?,
        glanceSnapshot: @escaping @MainActor (BrowserWindowState) -> GlanceSnapshot?,
        windowOwnedWebView: @escaping @MainActor (Tab, UUID) -> WKWebView?
    ) {
        self.activeWindow = activeWindow
        self.selectedTab = selectedTab
        self.glanceSnapshot = glanceSnapshot
        self.windowOwnedWebView = windowOwnedWebView
    }

    func resolve(in windowState: BrowserWindowState) -> ActivePageResolution? {
        if let glance = glanceSnapshot(windowState) {
            return ActivePageResolution(
                source: .glancePreview,
                windowState: windowState,
                tab: glance.tab,
                url: glance.url,
                canonicalWebView: glance.webView
            )
        }

        guard let tab = selectedTab(windowState) else { return nil }
        return ActivePageResolution(
            source: .selectedTab,
            windowState: windowState,
            tab: tab,
            url: tab.url,
            canonicalWebView: windowOwnedWebView(tab, windowState.id)
        )
    }

    func resolveActiveWindow() -> ActivePageResolution? {
        guard let windowState = activeWindow() else { return nil }
        return resolve(in: windowState)
    }
}
