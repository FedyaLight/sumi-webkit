import Foundation
import WebKit

extension Tab {
    func updateTitle(from webView: WKWebView) {
        navigationRuntime.titleUpdateOwner.updateTitle(
            from: webView,
            context: titleUpdateContext()
        )
    }

    @discardableResult
    func acceptResolvedDisplayTitle(_ title: String, url candidateURL: URL? = nil) -> Bool {
        navigationRuntime.titleUpdateOwner.acceptResolvedDisplayTitle(
            title,
            url: candidateURL,
            context: titleUpdateContext()
        )
    }

    func resolvedHistoryTitle(for candidateURL: URL) -> String {
        navigationRuntime.titleUpdateOwner.resolvedHistoryTitle(
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
                self.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind
            },
            scheduleRuntimeStatePersistence: {
                self.navigationRuntime.persistenceCallbacks.scheduleRuntimeStatePersistence(self)
            },
            notifyTitleChangedToExtensions: {
                self.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
                    self,
                    [.title]
                )
            },
            recordHistoryTitle: { title in
                self.navigationRuntime.historyRecorder.updateTitle(title, tab: self)
            }
        )
    }
}
