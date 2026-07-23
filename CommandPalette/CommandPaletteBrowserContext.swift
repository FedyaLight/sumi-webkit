import Foundation

@MainActor
struct CommandPaletteFaviconContext {
    let partition: SumiFaviconPartition
    let imageReader: any BrowserFaviconImageReading
    let prefetch: any BrowserFaviconPrefetchScheduling
}

@MainActor
final class CommandPaletteBrowserContext {
    let currentProfileId: UUID?
    let favicon: CommandPaletteFaviconContext

    private let configureSearchManagerHandler: (SearchManager) -> Void
    private let updateDraftHandler: (BrowserWindowState, String) -> Void
    private let dismissHandler: (BrowserWindowState, Bool) -> Void
    private let deleteHistoryEntryHandler: (HistoryListItem) async -> Void
    private let commitNavigatesCurrentTabHandler: (BrowserWindowState) -> Bool
    private let commitNavigationHandler: (String, BrowserWindowState) -> Void
    private let commitSuggestionHandler: (SearchManager.SearchSuggestion, BrowserWindowState) -> Void
    private let offersCommandSuggestionsHandler: (BrowserWindowState) -> Bool

    init(
        currentProfileId: UUID?,
        favicon: CommandPaletteFaviconContext,
        configureSearchManager: @escaping (SearchManager) -> Void,
        updateDraft: @escaping (BrowserWindowState, String) -> Void,
        dismiss: @escaping (BrowserWindowState, Bool) -> Void,
        deleteHistoryEntry: @escaping (HistoryListItem) async -> Void,
        commitNavigatesCurrentTab: @escaping (BrowserWindowState) -> Bool,
        commitNavigation: @escaping (String, BrowserWindowState) -> Void,
        commitSuggestion: @escaping (SearchManager.SearchSuggestion, BrowserWindowState) -> Void,
        offersCommandSuggestions: @escaping (BrowserWindowState) -> Bool
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
        self.offersCommandSuggestionsHandler = offersCommandSuggestions
    }

    func configureSearchManager(_ searchManager: SearchManager) {
        configureSearchManagerHandler(searchManager)
    }

    func updateCommandPaletteDraft(
        in windowState: BrowserWindowState,
        text: String
    ) {
        updateDraftHandler(windowState, text)
    }

    func dismissCommandPalette(
        in windowState: BrowserWindowState,
        preserveDraft: Bool
    ) {
        dismissHandler(windowState, preserveDraft)
    }

    func deleteHistoryEntry(_ entry: HistoryListItem) async {
        await deleteHistoryEntryHandler(entry)
    }

    func commandPaletteCommitNavigatesCurrentTab(in windowState: BrowserWindowState) -> Bool {
        commitNavigatesCurrentTabHandler(windowState)
    }

    func commitCommandPaletteNavigation(
        to urlString: String,
        in windowState: BrowserWindowState
    ) {
        commitNavigationHandler(urlString, windowState)
    }

    func commitCommandPaletteSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState
    ) {
        commitSuggestionHandler(suggestion, windowState)
    }

    func offersCommandSuggestions(in windowState: BrowserWindowState) -> Bool {
        offersCommandSuggestionsHandler(windowState)
    }
}
