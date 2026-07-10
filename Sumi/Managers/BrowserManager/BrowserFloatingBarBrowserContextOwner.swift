import Foundation

@MainActor
final class BrowserFloatingBarBrowserContextOwner {
    private let currentProfileId: @MainActor () -> UUID?
    private let faviconContext: @MainActor () -> FloatingBarFaviconContext
    private let configureSearchManager: @MainActor (SearchManager) -> Void
    private let updateDraft: @MainActor (BrowserWindowState, String) -> Void
    private let dismiss: @MainActor (BrowserWindowState, Bool) -> Void
    private let deleteHistoryEntry: @MainActor (HistoryListItem) async -> Void
    private let commitNavigatesCurrentTab: @MainActor (BrowserWindowState) -> Bool
    private let commitNavigation: @MainActor (String, BrowserWindowState) -> Void
    private let commitSuggestion: @MainActor (SearchManager.SearchSuggestion, BrowserWindowState) -> Void

    init(
        currentProfileId: @escaping @MainActor () -> UUID?,
        faviconContext: @escaping @MainActor () -> FloatingBarFaviconContext,
        configureSearchManager: @escaping @MainActor (SearchManager) -> Void,
        updateDraft: @escaping @MainActor (BrowserWindowState, String) -> Void,
        dismiss: @escaping @MainActor (BrowserWindowState, Bool) -> Void,
        deleteHistoryEntry: @escaping @MainActor (HistoryListItem) async -> Void,
        commitNavigatesCurrentTab: @escaping @MainActor (BrowserWindowState) -> Bool,
        commitNavigation: @escaping @MainActor (String, BrowserWindowState) -> Void,
        commitSuggestion: @escaping @MainActor (SearchManager.SearchSuggestion, BrowserWindowState) -> Void
    ) {
        self.currentProfileId = currentProfileId
        self.faviconContext = faviconContext
        self.configureSearchManager = configureSearchManager
        self.updateDraft = updateDraft
        self.dismiss = dismiss
        self.deleteHistoryEntry = deleteHistoryEntry
        self.commitNavigatesCurrentTab = commitNavigatesCurrentTab
        self.commitNavigation = commitNavigation
        self.commitSuggestion = commitSuggestion
    }

    convenience init(browserManager: BrowserManager) {
        let dataServices = browserManager.dataServices
        self.init(
            currentProfileId: { [weak browserManager] in
                browserManager?.currentProfile?.id
            },
            faviconContext: { [weak browserManager] in
                FloatingBarFaviconContext(
                    partition: dataServices.faviconService.partition(profile: browserManager?.currentProfile),
                    imageReader: dataServices.faviconCapabilities.images,
                    prefetch: dataServices.faviconCapabilities.prefetch
                )
            },
            configureSearchManager: { [weak browserManager] searchManager in
                guard let browserManager else { return }
                searchManager.setTabManager(browserManager.tabManager)
                searchManager.setHistoryManager(browserManager.historyManager)
                searchManager.setBookmarkManager(browserManager.bookmarkManager)
                searchManager.updateProfileContext()
            },
            updateDraft: { [weak browserManager] windowState, text in
                browserManager?.urlBarBundle.floatingBarRoutingOwner.updateFloatingBarDraft(in: windowState, text: text)
            },
            dismiss: { [weak browserManager] windowState, preserveDraft in
                browserManager?.urlBarBundle.floatingBarRoutingOwner.dismissFloatingBar(
                    in: windowState,
                    preserveDraft: preserveDraft,
                    cancelEmptySplitPlaceholder: true
                )
            },
            deleteHistoryEntry: { [weak browserManager] entry in
                guard let browserManager else { return }
                await browserManager.historyManager.delete(
                    query: BrowserFloatingBarBrowserContextOwner.historyDeletionQuery(for: entry)
                )
            },
            commitNavigatesCurrentTab: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.floatingBarRoutingOwner.floatingBarCommitNavigatesCurrentTab(in: windowState) ?? false
            },
            commitNavigation: { [weak browserManager] urlString, windowState in
                browserManager?.urlBarBundle.floatingBarRoutingOwner.commitFloatingBarNavigation(
                    to: urlString,
                    in: windowState
                )
            },
            commitSuggestion: { [weak browserManager] suggestion, windowState in
                browserManager?.urlBarBundle.floatingBarRoutingOwner.commitFloatingBarSuggestion(
                    suggestion,
                    in: windowState
                )
            }
        )
    }

    var context: FloatingBarBrowserContext {
        FloatingBarBrowserContext(
            currentProfileId: currentProfileId(),
            favicon: faviconContext(),
            configureSearchManager: configureSearchManager,
            updateDraft: updateDraft,
            dismiss: dismiss,
            deleteHistoryEntry: deleteHistoryEntry,
            commitNavigatesCurrentTab: commitNavigatesCurrentTab,
            commitNavigation: commitNavigation,
            commitSuggestion: commitSuggestion
        )
    }

    static func historyDeletionQuery(for entry: HistoryListItem) -> HistoryQuery {
        if let visitID = entry.visitID {
            return .visits([visitID])
        }
        return .domainFilter([entry.siteDomain ?? entry.domain])
    }
}
