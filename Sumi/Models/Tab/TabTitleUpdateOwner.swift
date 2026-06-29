import Foundation
import WebKit

@MainActor
struct TabTitleUpdateContext {
    let currentURL: () -> URL
    let existingWebView: () -> WKWebView?
    let currentName: () -> String
    let setName: (String) -> Void
    let representsSumiEmptySurface: () -> Bool
    let pendingMainFrameNavigationKind: () -> TabMainFrameNavigationKind?
    let scheduleRuntimeStatePersistence: () -> Void
    let notifyTitleChangedToExtensions: () -> Void
    let recordHistoryTitle: (String) -> Void
}

@MainActor
final class TabTitleUpdateOwner {
    func updateTitle(from webView: WKWebView, context: TabTitleUpdateContext) {
        let trimmedTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedTitle, !trimmedTitle.isEmpty else { return }

        if context.currentName() != trimmedTitle {
            context.setName(trimmedTitle)
            if context.pendingMainFrameNavigationKind() != .backForward {
                context.scheduleRuntimeStatePersistence()
            }
            context.notifyTitleChangedToExtensions()
        }

        context.recordHistoryTitle(trimmedTitle)

        if let currentItem = webView.backForwardList.currentItem,
           currentItem.url == (webView.url ?? context.currentURL()),
           !webView.isLoading {
            currentItem.tabTitle = trimmedTitle
        }
    }

    @discardableResult
    func acceptResolvedDisplayTitle(
        _ title: String,
        url candidateURL: URL? = nil,
        context: TabTitleUpdateContext
    ) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        _ = candidateURL
        guard trimmedTitle != context.currentName() else { return false }
        context.setName(trimmedTitle)
        if context.pendingMainFrameNavigationKind() != .backForward {
            context.scheduleRuntimeStatePersistence()
        }
        context.notifyTitleChangedToExtensions()
        context.recordHistoryTitle(trimmedTitle)
        return true
    }

    func resolvedHistoryTitle(for candidateURL: URL, context: TabTitleUpdateContext) -> String {
        let webViewTitle = context.existingWebView()?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let webViewTitle, !webViewTitle.isEmpty {
            return webViewTitle
        }

        let currentName = context.currentName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentName.isEmpty, !context.representsSumiEmptySurface() {
            return currentName
        }

        return candidateURL.sumiSuggestedTitlePlaceholder ?? candidateURL.absoluteString
    }
}
