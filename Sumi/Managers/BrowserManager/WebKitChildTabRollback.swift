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
        let admission: ExactTabResidenceAdmission?
        switch residence {
        case .regular(let spaceID):
            admission = ExactTabResidenceAdmission.regular(
                tab,
                in: spaceID,
                tabs: tabs
            )
        case .ephemeral:
            admission = ExactTabResidenceAdmission.ephemeral(
                tab,
                in: sourceWindow
            )
        }
        guard let admission else { return }

        tabs.structuralPersistence.cancelRuntimeStatePersistence(for: tab.id)
        tab.cleanupCloneWebView(webView)
        guard admission.remove(
            tabs: tabs,
            currentSpaceID: sourceWindow.currentSpaceId
        ) else { return }

        switch residence {
        case .regular:
            tabs.tabCollectionMembershipOwner.detach(tab)
            tabs.structuralPersistence.scheduleStructuralPersistence()
        case .ephemeral(let previousTabID):
            if sourceWindow.currentTabId == tab.id {
                sourceWindow.currentTabId = previousTabID
            }
        }
    }
}
