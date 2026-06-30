import Foundation
import WebKit

extension Tab {
    func updateTitle(from webView: WKWebView) {
        titleUpdateOwner.updateTitle(
            from: webView,
            context: titleUpdateContext()
        )
    }

    @discardableResult
    func acceptResolvedDisplayTitle(_ title: String, url candidateURL: URL? = nil) -> Bool {
        titleUpdateOwner.acceptResolvedDisplayTitle(
            title,
            url: candidateURL,
            context: titleUpdateContext()
        )
    }

    func resolvedHistoryTitle(for candidateURL: URL) -> String {
        titleUpdateOwner.resolvedHistoryTitle(
            for: candidateURL,
            context: titleUpdateContext()
        )
    }

    private func titleUpdateContext() -> TabTitleUpdateContext {
        TabTitleUpdateContext(
            currentURL: { self.url },
            existingWebView: { self.existingWebView },
            currentName: { self.name },
            setName: { title in
                self.name = title
            },
            representsSumiEmptySurface: {
                self.representsSumiEmptySurface
            },
            pendingMainFrameNavigationKind: {
                self.pendingMainFrameNavigationKind
            },
            scheduleRuntimeStatePersistence: {
                self.persistenceRuntimeCallbacks.scheduleRuntimeStatePersistence(self)
            },
            notifyTitleChangedToExtensions: {
                self.browserManager?.extensionsModule.notifyTabPropertiesChangedIfLoaded(
                    self,
                    properties: [.title]
                )
            },
            recordHistoryTitle: { title in
                self.historyRecorder.updateTitle(title, tab: self)
            }
        )
    }
}
