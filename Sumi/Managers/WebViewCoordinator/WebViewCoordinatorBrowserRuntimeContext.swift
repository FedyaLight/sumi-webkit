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
    let closeTab: (Tab, BrowserWindowState) -> Void
    let removeTab: (UUID) -> Void
    let refreshCompositor: (BrowserWindowState) -> Void
    let notifyTabActivatedIfLoaded: (Tab) -> Void
    let needsInitialDocumentExtensionContextLoad: (UUID) -> Bool
    let ensureInitialDocumentExtensionContextsLoaded: (UUID) async -> Void
    let cleanupUserScripts: (WKUserContentController, UUID) -> Void
    let globallyVisibleTabIDs: @MainActor @Sendable () -> Set<UUID>
}
