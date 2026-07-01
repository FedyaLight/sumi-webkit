import Foundation
import WebKit

@MainActor
struct WebViewCoordinatorBrowserRuntimeContext {
    let tabManager: () -> TabManager
    let tab: (UUID) -> Tab?
    let regularTabs: () -> [Tab]
    let pinnedTabs: () -> [Tab]
    let allWindows: () -> [BrowserWindowState]
    let window: (UUID) -> BrowserWindowState?
    let windowContaining: (Tab) -> BrowserWindowState?
    let currentTab: (BrowserWindowState) -> Tab?
    let handleUnprotectedWebViewDidClose: (WKWebView) -> Bool
    let refreshCompositor: (BrowserWindowState) -> Void
    let notifyTabActivatedIfLoaded: (Tab) -> Void
    let globallyVisibleTabIDs: @MainActor @Sendable () -> Set<UUID>
}
