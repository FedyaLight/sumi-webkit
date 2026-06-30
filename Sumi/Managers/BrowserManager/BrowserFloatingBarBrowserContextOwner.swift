import Foundation

@MainActor
final class BrowserFloatingBarBrowserContextOwner {
    struct Dependencies {
        let currentProfileId: @MainActor () -> UUID?
        let faviconContext: @MainActor () -> FloatingBarFaviconContext
        let configureSearchManager: @MainActor (SearchManager) -> Void
        let updateDraft: @MainActor (BrowserWindowState, String) -> Void
        let dismiss: @MainActor (BrowserWindowState, Bool) -> Void
        let deleteHistoryEntry: @MainActor (HistoryListItem) async -> Void
        let commitNavigatesCurrentTab: @MainActor (BrowserWindowState) -> Bool
        let commitNavigation: @MainActor (String, BrowserWindowState) -> Void
        let commitSuggestion: @MainActor (SearchManager.SearchSuggestion, BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var context: FloatingBarBrowserContext {
        FloatingBarBrowserContext(
            currentProfileId: dependencies.currentProfileId(),
            favicon: dependencies.faviconContext(),
            configureSearchManager: dependencies.configureSearchManager,
            updateDraft: dependencies.updateDraft,
            dismiss: dependencies.dismiss,
            deleteHistoryEntry: dependencies.deleteHistoryEntry,
            commitNavigatesCurrentTab: dependencies.commitNavigatesCurrentTab,
            commitNavigation: dependencies.commitNavigation,
            commitSuggestion: dependencies.commitSuggestion
        )
    }

    static func historyDeletionQuery(for entry: HistoryListItem) -> HistoryQuery {
        if let visitID = entry.visitID {
            return .visits([visitID])
        }
        return .domainFilter([entry.siteDomain ?? entry.domain])
    }
}

extension BrowserFloatingBarBrowserContextOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let dataServices = browserManager.dataServices
        return Self(
            currentProfileId: { [weak browserManager] in
                browserManager?.currentProfile?.id
            },
            faviconContext: { [weak browserManager] in
                FloatingBarFaviconContext(
                    partition: dataServices.faviconService.partition(profile: browserManager?.currentProfile),
                    imageService: dataServices.faviconImageService
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
                browserManager?.updateFloatingBarDraft(in: windowState, text: text)
            },
            dismiss: { [weak browserManager] windowState, preserveDraft in
                browserManager?.dismissFloatingBar(in: windowState, preserveDraft: preserveDraft)
            },
            deleteHistoryEntry: { [weak browserManager] entry in
                guard let browserManager else { return }
                await browserManager.historyManager.delete(
                    query: BrowserFloatingBarBrowserContextOwner.historyDeletionQuery(for: entry)
                )
            },
            commitNavigatesCurrentTab: { [weak browserManager] windowState in
                browserManager?.floatingBarCommitNavigatesCurrentTab(in: windowState) ?? false
            },
            commitNavigation: { [weak browserManager] urlString, windowState in
                browserManager?.commitFloatingBarNavigation(
                    to: urlString,
                    in: windowState
                )
            },
            commitSuggestion: { [weak browserManager] suggestion, windowState in
                browserManager?.commitFloatingBarSuggestion(
                    suggestion,
                    in: windowState
                )
            }
        )
    }
}
