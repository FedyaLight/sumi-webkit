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
        webView: WKWebView?,
        residence: WebKitChildTabResidence,
        sourceWindow: BrowserWindowState,
        residences: BrowserTabResidenceAuthority
    ) {
        switch residence {
        case .regular(let spaceID):
            guard sourceWindow.isIncognito == false,
                  tab.spaceId == spaceID else { return }
        case .ephemeral:
            guard sourceWindow.isIncognito else { return }
        }
        guard let admission = residences.admitRemoval(
            of: tab,
            from: sourceWindow
        ) else { return }

        if let webView {
            tab.cleanupCloneWebView(webView)
        }
        guard residences.commitRemoval(
            admission,
            currentSpaceID: sourceWindow.currentSpaceId
        ) else { return }

        switch residence {
        case .regular:
            break
        case .ephemeral(let previousTabID):
            if sourceWindow.currentTabId == tab.id {
                sourceWindow.currentTabId = previousTabID
            }
        }
    }
}
