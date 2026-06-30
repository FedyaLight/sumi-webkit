import Foundation

@MainActor
struct FloatingBarFaviconContext {
    let partition: SumiFaviconPartition
    let imageService: any BrowserFaviconImageServicing
}

@MainActor
struct FloatingBarBrowserContext {
    let currentProfileId: UUID?
    let favicon: FloatingBarFaviconContext

    private let configureSearchManagerHandler: (SearchManager) -> Void
    private let updateDraftHandler: (BrowserWindowState, String) -> Void
    private let dismissHandler: (BrowserWindowState, Bool) -> Void
    private let deleteHistoryEntryHandler: (HistoryListItem) async -> Void
    private let commitNavigatesCurrentTabHandler: (BrowserWindowState) -> Bool
    private let commitNavigationHandler: (String, BrowserWindowState) -> Void
    private let commitSuggestionHandler: (SearchManager.SearchSuggestion, BrowserWindowState) -> Void

    init(
        currentProfileId: UUID?,
        favicon: FloatingBarFaviconContext,
        configureSearchManager: @escaping (SearchManager) -> Void,
        updateDraft: @escaping (BrowserWindowState, String) -> Void,
        dismiss: @escaping (BrowserWindowState, Bool) -> Void,
        deleteHistoryEntry: @escaping (HistoryListItem) async -> Void,
        commitNavigatesCurrentTab: @escaping (BrowserWindowState) -> Bool,
        commitNavigation: @escaping (String, BrowserWindowState) -> Void,
        commitSuggestion: @escaping (SearchManager.SearchSuggestion, BrowserWindowState) -> Void
    ) {
        self.currentProfileId = currentProfileId
        self.favicon = favicon
        self.configureSearchManagerHandler = configureSearchManager
        self.updateDraftHandler = updateDraft
        self.dismissHandler = dismiss
        self.deleteHistoryEntryHandler = deleteHistoryEntry
        self.commitNavigatesCurrentTabHandler = commitNavigatesCurrentTab
        self.commitNavigationHandler = commitNavigation
        self.commitSuggestionHandler = commitSuggestion
    }

    func configureSearchManager(_ searchManager: SearchManager) {
        configureSearchManagerHandler(searchManager)
    }

    func updateFloatingBarDraft(
        in windowState: BrowserWindowState,
        text: String
    ) {
        updateDraftHandler(windowState, text)
    }

    func dismissFloatingBar(
        in windowState: BrowserWindowState,
        preserveDraft: Bool
    ) {
        dismissHandler(windowState, preserveDraft)
    }

    func deleteHistoryEntry(_ entry: HistoryListItem) async {
        await deleteHistoryEntryHandler(entry)
    }

    func floatingBarCommitNavigatesCurrentTab(in windowState: BrowserWindowState) -> Bool {
        commitNavigatesCurrentTabHandler(windowState)
    }

    func commitFloatingBarNavigation(
        to urlString: String,
        in windowState: BrowserWindowState
    ) {
        commitNavigationHandler(urlString, windowState)
    }

    func commitFloatingBarSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState
    ) {
        commitSuggestionHandler(suggestion, windowState)
    }
}
