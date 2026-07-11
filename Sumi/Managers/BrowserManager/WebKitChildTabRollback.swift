import Foundation
import WebKit

enum WebKitChildTabResidence {
    case regular(spaceID: UUID)
    case ephemeral(previousTabID: UUID?)
}

/// Reverses the complete model and physical-WebView side of a child-tab
/// creation that failed before canonical placement committed.
@MainActor
enum WebKitChildTabRollback {
    static func discard(
        _ tab: Tab,
        webView: WKWebView,
        residence: WebKitChildTabResidence,
        sourceWindow: BrowserWindowState,
        tabs: TabManager
    ) {
        tab.cleanupCloneWebView(webView)
        tabs.structuralPersistence.cancelRuntimeStatePersistence(for: tab.id)

        switch residence {
        case .regular(let spaceID):
            if tabs.regularTabCollectionOwner.remove(
                tab.id,
                from: spaceID,
                currentSpaceId: sourceWindow.currentSpaceId
            ) != nil {
                tabs.tabCollectionMembershipOwner.detach(tab)
                tabs.structuralPersistence.scheduleStructuralPersistence()
            }
        case .ephemeral(let previousTabID):
            sourceWindow.ephemeralTabs.removeAll { $0 === tab }
            if sourceWindow.currentTabId == tab.id {
                sourceWindow.currentTabId = previousTabID
            }
        }
    }
}
