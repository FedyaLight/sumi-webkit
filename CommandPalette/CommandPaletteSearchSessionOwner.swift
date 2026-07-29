import Observation
import SumiDomain
import Foundation

enum CommandPaletteMode: Equatable {
    case everything
    case actions
    case siteSearch(SumiSearchEngine)
}

@Observable
@MainActor
final class CommandPaletteSearchSessionOwner {
    private let searchManager: SearchManager
    var text = "" {
        didSet {
            resultListTopRequestID &+= 1
            retainPublishedSuggestionsForQueryTransition()
            rebuildSuggestionSnapshot()
            selectedRowID = visibleRows.first?.id
        }
    }
    private(set) var resultListTopRequestID: UInt64 = 0
    var selectedRowID: CommandPaletteRow.ID?
    var hoveredRowID: CommandPaletteRow.ID?
    private(set) var isWaitingForSearchDebounce = false
    private(set) var committedSuggestionLayoutCount = 0
    private(set) var visibleRows: [CommandPaletteRow] = []
    private(set) var availableSpaces: [CommandPaletteSpacePresentation] = []
    private(set) var availableExtensionActions:
        [CommandPaletteExtensionPresentation] = []
    private(set) var availableBrowserActions:
        [ShortcutAction: CommandPaletteBrowserActionPresentation]?
    private(set) var mode: CommandPaletteMode = .everything {
        didSet {
            rebuildSuggestionSnapshot()
        }
    }

    private let commandProvider = CommandPaletteCommandSuggestionProvider()
    private var searchDebouncer = MainActorDebouncedTask()
    private var searchSuggestionSourceQuery: String?
    private var requestedSearchSuggestionQuery: String?
    private var retainedSearchSuggestions:
        [SearchManager.SearchSuggestion] = []

    init(searchManager: SearchManager = SearchManager()) {
        self.searchManager = searchManager
        searchManager.onStateChange = { [weak self] in
            self?.handleSearchManagerStateChanged()
        }
    }

    private func makeVisibleSuggestions() -> [SearchManager.SearchSuggestion] {
        if activeSiteSearch != nil {
            guard searchSuggestionsMatchCurrentQuery else { return [] }
            return searchManager.suggestions.filter {
                if case .search = $0.type { return true }
                return false
            }
        }
        let actionSuggestions = commandProvider.suggestions(
            for: text,
            showsAllWhenEmpty: mode == .actions,
            availableActions: availableBrowserActions
        )
        let spaceSuggestions = matchingSpaceSuggestions(
            showsAllWhenEmpty: mode == .actions
        )
        let extensionSuggestions = matchingExtensionSuggestions(
            showsAllWhenEmpty: mode == .actions
        )
        if mode == .actions {
            return actionSuggestions + spaceSuggestions + extensionSuggestions
        }

        var candidates: [SearchManager.SearchSuggestion] = []
        let trimmedQuery = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !trimmedQuery.isEmpty {
            candidates.append(
                SuggestionDeduplicationPolicy.directURLSuggestion(
                    for: trimmedQuery
                ) ?? SearchManager.SearchSuggestion(
                    text: trimmedQuery,
                    type: .search
                )
            )
        }
        candidates += actionSuggestions
        candidates += spaceSuggestions
        candidates += extensionSuggestions
        if searchSuggestionsMatchCurrentQuery {
            candidates += searchManager.suggestions
        } else {
            if searchManager.suggestionSourceQuery == normalizedCurrentQuery {
                candidates += searchManager.suggestions
            }
            candidates += retainedSearchSuggestions
        }

        var seenIDs = Set<SearchManager.SearchSuggestion.ID>()
        return candidates.filter { seenIDs.insert($0.id).inserted }
    }

    var visibleSuggestionLayoutCount: Int {
        CommandPaletteLayoutPolicy.layoutCount(forVisibleCount: visibleRows.count)
    }

    var selectedSuggestionIndex: Int {
        get {
            guard let selectedRowID else { return -1 }
            return visibleRows.firstIndex {
                $0.id == selectedRowID
            } ?? -1
        }
        set {
            guard visibleRows.indices.contains(newValue) else {
                selectedRowID = nil
                return
            }
            selectedRowID = visibleRows[newValue].id
        }
    }

    var suggestionLayoutCount: Int {
        committedSuggestionLayoutCount
    }

    var activeSiteSearch: SumiSearchEngine? {
        guard case .siteSearch(let site) = mode else { return nil }
        return site
    }

    func siteSearchMatch(in searchEngines: [SumiSearchEngine]) -> SumiSearchEngine? {
        guard mode == .everything else { return nil }
        return SumiSearchEngine.match(for: text, in: searchEngines)
    }

    func urlBarPlaceholderString() -> String {
        if mode == .actions {
            return String(localized: "Search Actions...")
        }
        if let site = activeSiteSearch {
            return String(localized: "Search \(site.name)...")
        }
        return String(localized: "Search...")
    }

    func isWaitingForSuggestions() -> Bool {
        CommandPaletteLayoutPolicy.shouldWaitForSuggestionLayout(
            isDebouncing: isWaitingForSearchDebounce,
            isLoading: searchManager.isLoadingSuggestions,
            visibleLayoutCount: visibleSuggestionLayoutCount
        )
    }

    func handleTextChanged(
        _ newValue: String,
        isCommandPaletteVisible: Bool,
        presentationReason: CommandPalettePresentationReason,
        windowState: BrowserWindowState
    ) {
        if mode == .actions {
            searchDebouncer.cancel()
            setWaitingForSearchDebounce(false)
            searchManager.clearSuggestions()
            searchSuggestionSourceQuery = nil
            requestedSearchSuggestionQuery = nil
            retainedSearchSuggestions = []
            rebuildSuggestionSnapshot()
            selectedRowID = visibleRows.first?.id
            commitSuggestionLayoutCount()
            return
        }

        scheduleSearchSuggestions(
            for: newValue,
            isCommandPaletteVisible: isCommandPaletteVisible,
            presentationReason: presentationReason,
            windowState: windowState
        )
        selectedRowID = visibleRows.first?.id
    }

    func scheduleSearchSuggestions(
        for query: String,
        isCommandPaletteVisible: Bool,
        presentationReason: CommandPalettePresentationReason,
        windowState: BrowserWindowState
    ) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchDebouncer.cancel()
            setWaitingForSearchDebounce(false)
            requestedSearchSuggestionQuery = nil
            refreshEmptyStateSuggestionsIfNeeded(
                isCommandPaletteVisible: isCommandPaletteVisible,
                presentationReason: presentationReason,
                windowState: windowState
            )
            return
        }

        searchManager.cancelSuggestionRequests()
        requestedSearchSuggestionQuery = trimmedQuery
        setWaitingForSearchDebounce(true)
        searchDebouncer.schedule(delayNanoseconds: 160_000_000) { [weak self] in
            guard let self else { return }
            self.setWaitingForSearchDebounce(false)
            self.searchManager.searchSuggestions(
                for: trimmedQuery,
                windowState: windowState
            )
        }
    }

    func refreshEmptyStateSuggestionsIfNeeded(
        isCommandPaletteVisible: Bool,
        presentationReason: CommandPalettePresentationReason,
        windowState: BrowserWindowState
    ) {
        guard isCommandPaletteVisible,
              activeSiteSearch == nil,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        searchDebouncer.cancel()
        setWaitingForSearchDebounce(false)
        requestedSearchSuggestionQuery = nil
        if presentationReason == .splitTabPicker {
            searchSuggestionSourceQuery = ""
            setCommittedSuggestionLayoutCount(
                CommandPaletteLayoutPolicy.suggestionsVisibleRowLimit
            )
            searchManager.showActiveTabSuggestions(for: windowState)
            rebuildSuggestionSnapshot()
        } else {
            searchSuggestionSourceQuery = ""
            setCommittedSuggestionLayoutCount(
                CommandPaletteLayoutPolicy.suggestionsVisibleRowLimit
            )
            searchManager.showContextualSuggestions(
                limit: CommandPaletteLayoutPolicy.suggestionsVisibleRowLimit,
                windowState: windowState
            )
            rebuildSuggestionSnapshot()
        }
    }

    func handleProfileContextChanged(
        isCommandPaletteVisible: Bool,
        presentationReason: CommandPalettePresentationReason,
        windowState: BrowserWindowState
    ) {
        guard isCommandPaletteVisible else { return }
        searchManager.clearSuggestions()
        searchSuggestionSourceQuery = nil
        requestedSearchSuggestionQuery = nil
        retainedSearchSuggestions = []
        rebuildSuggestionSnapshot()
        handleTextChanged(
            text,
            isCommandPaletteVisible: true,
            presentationReason: presentationReason,
            windowState: windowState
        )
    }

    func reloadAfterHistoryDeletion(
        isCommandPaletteVisible: Bool,
        presentationReason: CommandPalettePresentationReason,
        windowState: BrowserWindowState
    ) {
        if normalizedCurrentQuery.isEmpty {
            refreshEmptyStateSuggestionsIfNeeded(
                isCommandPaletteVisible: isCommandPaletteVisible,
                presentationReason: presentationReason,
                windowState: windowState
            )
        } else {
            searchManager.searchSuggestions(
                for: normalizedCurrentQuery,
                windowState: windowState
            )
        }
    }

    func updateAvailableSpaces(
        _ spaces: [CommandPaletteSpacePresentation]
    ) {
        availableSpaces = spaces
        rebuildSuggestionSnapshot()
    }

    func updateAvailableExtensionActions(
        _ actions: [CommandPaletteExtensionPresentation]
    ) {
        availableExtensionActions = actions
        rebuildSuggestionSnapshot()
    }

    func updateAvailableBrowserActions(
        _ actions: Set<ShortcutAction>
    ) {
        updateAvailableBrowserActions(
            actions.map {
                CommandPaletteBrowserActionPresentation(action: $0)
            }
        )
    }

    func updateAvailableBrowserActions(
        _ presentations: [CommandPaletteBrowserActionPresentation]
    ) {
        availableBrowserActions = Dictionary(
            presentations.map { ($0.action, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        rebuildSuggestionSnapshot()
    }

    private func handleSuggestionsChanged() {
        handleSuggestionsChanged(
            sourceQuery: searchManager.suggestionSourceQuery,
            publicationIsSettled:
                searchManager.suggestionPublicationIsSettled
        )
    }

    private func handleSuggestionsChanged(
        sourceQuery: String?,
        publicationIsSettled: Bool
    ) {
        if publicationIsSettled {
            if let sourceQuery {
                searchSuggestionSourceQuery = sourceQuery
            } else if searchSuggestionSourceQuery == nil,
                      requestedSearchSuggestionQuery == nil {
                searchSuggestionSourceQuery = normalizedCurrentQuery
            }
            if searchSuggestionsMatchCurrentQuery {
                retainedSearchSuggestions = []
            }
        }
        let previousVisibleIDs = visibleRows.map(\.id)
        rebuildSuggestionSnapshot()
        let count = visibleRows.count
        if count == 0 {
            selectedRowID = nil
        } else if selectedRowID == nil
                    || !visibleRows.contains(where: {
                        $0.id == selectedRowID
                    }) {
            selectedRowID = visibleRows.first?.id
        }
        if visibleRows.map(\.id) != previousVisibleIDs,
           selectedRowID == visibleRows.first?.id {
            resultListTopRequestID &+= 1
        }
        commitSuggestionLayoutCountIfReady()
    }

    private func handleSuggestionLoadingChanged() {
        if !searchManager.isLoadingSuggestions {
            finishSearchSuggestionRequestIfNeeded()
            commitSuggestionLayoutCountIfReady()
        }
    }

    func commitSuggestionLayoutCountIfReady() {
        guard !isWaitingForSuggestions() else { return }
        commitSuggestionLayoutCount()
    }

    func commitSuggestionLayoutCount() {
        let nextCount = visibleSuggestionLayoutCount
        guard committedSuggestionLayoutCount != nextCount else { return }
        setCommittedSuggestionLayoutCount(nextCount)
    }

    func enterSiteSearch(_ site: SumiSearchEngine) {
        searchDebouncer.cancel()
        searchManager.clearSuggestions()
        searchSuggestionSourceQuery = nil
        requestedSearchSuggestionQuery = nil
        retainedSearchSuggestions = []
        setWaitingForSearchDebounce(false)
        mode = .siteSearch(site)
        text = ""
        selectedRowID = nil
    }

    func enterActionsMode() {
        guard mode == .everything,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        searchDebouncer.cancel()
        searchManager.clearSuggestions()
        searchSuggestionSourceQuery = nil
        requestedSearchSuggestionQuery = nil
        retainedSearchSuggestions = []
        setWaitingForSearchDebounce(false)
        resultListTopRequestID &+= 1
        mode = .actions
        selectedRowID = visibleRows.first?.id
        committedSuggestionLayoutCount =
            CommandPaletteLayoutPolicy.layoutCount(
                forVisibleCount: visibleRows.count
            )
    }

    @discardableResult
    func leaveScopedMode() -> Bool {
        guard mode != .everything else { return false }
        mode = .everything
        text = ""
        selectedRowID = nil
        searchManager.clearSuggestions()
        searchSuggestionSourceQuery = nil
        requestedSearchSuggestionQuery = nil
        retainedSearchSuggestions = []
        rebuildSuggestionSnapshot()
        return true
    }

    func navigateSuggestions(direction: Int) {
        let maxIndex = visibleRows.count - 1
        guard maxIndex >= 0 else {
            selectedRowID = nil
            return
        }

        let newIndex: Int
        if direction > 0 {
            newIndex = min(selectedSuggestionIndex + 1, maxIndex)
        } else {
            newIndex = max(selectedSuggestionIndex - 1, -1)
        }

        selectedSuggestionIndex = newIndex
    }

    func commitIntentForReturn() -> CommandPaletteCommitIntent? {
        if let selectedRowID,
           let selectedRow = visibleRows.first(where: {
               $0.id == selectedRowID
           }) {
            return commitIntent(for: selectedRow)
        }

        let trimmed = normalizedCurrentQuery
        guard !trimmed.isEmpty else { return nil }
        if let site = activeSiteSearch {
            return .siteSearch(site, query: trimmed)
        }
        return .browserNavigation(.input(trimmed))
    }

    func commitIntent(for rowID: CommandPaletteRow.ID) -> CommandPaletteCommitIntent? {
        guard let row = visibleRows.first(where: { $0.id == rowID }) else {
            return nil
        }
        return commitIntent(for: row)
    }

    func historyDeletionQuery(for rowID: CommandPaletteRow.ID) -> HistoryQuery? {
        guard let row = visibleRows.first(where: { $0.id == rowID }),
              case .deleteHistory(let query) = row.secondaryAction else {
            return nil
        }
        return query
    }

    func resetForHiddenBar() {
        searchDebouncer.cancel()
        isWaitingForSearchDebounce = false
        searchManager.clearSuggestions()
        searchSuggestionSourceQuery = nil
        requestedSearchSuggestionQuery = nil
        retainedSearchSuggestions = []
        text = ""
        mode = .everything
        selectedRowID = nil
        hoveredRowID = nil
        committedSuggestionLayoutCount = 0
        availableSpaces = []
        availableExtensionActions = []
        availableBrowserActions = nil
        rebuildSuggestionSnapshot()
    }

    func resetAfterCommit() {
        searchDebouncer.cancel()
        searchManager.clearSuggestions()
        searchSuggestionSourceQuery = nil
        requestedSearchSuggestionQuery = nil
        retainedSearchSuggestions = []
        text = ""
        mode = .everything
        selectedRowID = nil
        hoveredRowID = nil
        rebuildSuggestionSnapshot()
    }

    func cancelPendingSearch() {
        searchDebouncer.cancel()
    }

    private func setWaitingForSearchDebounce(_ isWaiting: Bool) {
        isWaitingForSearchDebounce = isWaiting
    }

    private func matchingSpaceSuggestions(
        showsAllWhenEmpty: Bool
    ) -> [SearchManager.SearchSuggestion] {
        let normalizedQuery = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
        return availableSpaces.compactMap { space in
            let title = space.title.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            let matches = normalizedQuery.isEmpty
                ? showsAllWhenEmpty
                : title.localizedStandardContains(normalizedQuery)
                    || "space".hasPrefix(normalizedQuery)
                    || "switch space".contains(normalizedQuery)
            guard matches else { return nil }
            return SearchManager.SearchSuggestion(
                text: String(localized: "Switch to \(space.title)"),
                type: .space(space)
            )
        }
    }

    private func rebuildSuggestionSnapshot() {
        visibleRows = makeVisibleSuggestions().map(makeRow)
    }

    private func makeRow(
        _ suggestion: SearchManager.SearchSuggestion
    ) -> CommandPaletteRow {
        switch suggestion.type {
        case .search:
            return CommandPaletteRow(
                id: rowID(for: suggestion),
                title: suggestion.text,
                subtitle: nil,
                icon: .systemSymbol("magnifyingglass"),
                accessory: .none,
                accessibilityLabel: String(
                    localized: "Search, \(suggestion.text)"
                ),
                activation: .input(suggestion.text),
                secondaryAction: nil
            )
        case .url:
            return CommandPaletteRow(
                id: rowID(for: suggestion),
                title: suggestion.text,
                subtitle: nil,
                icon: .systemSymbol("link"),
                accessory: .chip(String(localized: "Open URL")),
                accessibilityLabel: String(
                    localized: "Open URL, \(suggestion.text)"
                ),
                activation: .input(suggestion.text),
                secondaryAction: nil
            )
        case .tab(let tab):
            return CommandPaletteRow(
                id: rowID(for: suggestion),
                title: tab.name,
                subtitle: nil,
                icon: .tab(tab.faviconPresentation),
                accessory: .arrow(String(localized: "Switch to Tab")),
                accessibilityLabel: String(
                    localized: "Switch to tab, \(tab.name)"
                ),
                activation: .tab(tab.id),
                secondaryAction: nil
            )
        case .navigationTarget(let target):
            let icon: CommandPaletteRow.Icon =
                target.action == .switchToSplitView
                    ? .splitView(target.splitMembers)
                    : target.primaryURL.map(CommandPaletteRow.Icon.favicon)
                        ?? .systemSymbol("macwindow")
            let actionLabel = target.action == .switchToSplitView
                ? String(localized: "Switch to Split View")
                : String(localized: "Switch to Tab")
            let accessibilityLabel = target.action == .switchToSplitView
                ? String(localized: "Switch to split view, \(target.title)")
                : String(localized: "Switch to tab, \(target.title)")
            return CommandPaletteRow(
                id: rowID(for: suggestion),
                title: target.title,
                subtitle: nil,
                icon: icon,
                accessory: .arrow(actionLabel),
                accessibilityLabel: accessibilityLabel,
                activation: .navigationTarget(target.identity),
                secondaryAction: nil
            )
        case .history(let entry):
            let deletionQuery: HistoryQuery
            if let visitID = entry.visitID {
                deletionQuery = .visits([visitID])
            } else {
                deletionQuery = .domainFilter([
                    entry.siteDomain ?? entry.domain,
                ])
            }
            return CommandPaletteRow(
                id: rowID(for: suggestion),
                title: entry.displayTitle,
                subtitle: entry.displayURL,
                icon: .favicon(entry.url),
                accessory: .none,
                accessibilityLabel: String(
                    localized:
                        "Open history item, \(entry.displayTitle), \(entry.displayURL)"
                ),
                activation: .literalURL(entry.url.absoluteString),
                secondaryAction: .deleteHistory(deletionQuery)
            )
        case .bookmark(let bookmark):
            return CommandPaletteRow(
                id: rowID(for: suggestion),
                title: bookmark.title,
                subtitle: nil,
                icon: .systemSymbol("bookmark.fill"),
                accessory: .chip(String(localized: "Open Bookmark")),
                accessibilityLabel: String(
                    localized: "Open bookmark, \(bookmark.title)"
                ),
                activation: .literalURL(bookmark.url.absoluteString),
                secondaryAction: nil
            )
        case .command(let action):
            let presentation = availableBrowserActions?[action]
            return CommandPaletteRow(
                id: rowID(for: suggestion),
                title: suggestion.text,
                subtitle: nil,
                icon: .systemSymbol(action.commandPaletteSymbolName),
                accessory: .chip(
                    presentation?.shortcutLabel
                        ?? String(localized: "Run")
                ),
                accessibilityLabel: String(
                    localized: "Run command, \(suggestion.text)"
                ),
                activation: .browserAction(action),
                secondaryAction: nil
            )
        case .space(let space):
            return CommandPaletteRow(
                id: rowID(for: suggestion),
                title: suggestion.text,
                subtitle: nil,
                icon: .systemSymbol("rectangle.3.group"),
                accessory: .chip(String(localized: "Switch")),
                accessibilityLabel: String(
                    localized: "Switch space, \(suggestion.text)"
                ),
                activation: .space(space.id),
                secondaryAction: nil
            )
        case .extensionAction(let action):
            return CommandPaletteRow(
                id: rowID(for: suggestion),
                title: action.title,
                subtitle: nil,
                icon: .systemSymbol("puzzlepiece.extension"),
                accessory: .chip(String(localized: "Run")),
                accessibilityLabel: String(
                    localized: "Run extension action, \(action.title)"
                ),
                activation: .extensionAction(action.id),
                secondaryAction: nil
            )
        }
    }

    private func rowID(
        for suggestion: SearchManager.SearchSuggestion
    ) -> CommandPaletteRow.ID {
        switch suggestion.id {
        case .search(let text):
            return .search(text)
        case .url(let text):
            return .url(text)
        case .tab(let id):
            return .tab(id)
        case .navigationTarget(let identity):
            return .navigationTarget(identity)
        case .history(let id):
            return .history(id)
        case .bookmark(let id):
            return .bookmark(id)
        case .command(let action):
            return .command(action)
        case .space(let id):
            return .space(id)
        case .extensionAction(let id):
            return .extensionAction(id)
        }
    }

    private func commitIntent(
        for row: CommandPaletteRow
    ) -> CommandPaletteCommitIntent {
        if let site = activeSiteSearch {
            return .siteSearch(site, query: row.title)
        }
        switch row.activation {
        case .browserAction(let action):
            return .browserAction(action)
        case .space(let id):
            return .space(id)
        case .extensionAction(let id):
            return .extensionAction(id)
        case .input, .literalURL, .tab, .navigationTarget:
            return .browserNavigation(row.activation)
        }
    }

    private func retainPublishedSuggestionsForQueryTransition() {
        guard mode == .everything,
              !normalizedCurrentQuery.isEmpty,
              !searchSuggestionsMatchCurrentQuery
        else {
            retainedSearchSuggestions = []
            return
        }
        guard !searchManager.suggestions.isEmpty else { return }
        retainedSearchSuggestions = searchManager.suggestions
    }

    private func finishSearchSuggestionRequestIfNeeded() {
        guard !isWaitingForSearchDebounce,
              let requestedSearchSuggestionQuery,
              requestedSearchSuggestionQuery == normalizedCurrentQuery
        else { return }

        if let publishedQuery = searchManager.suggestionSourceQuery {
            searchSuggestionSourceQuery = publishedQuery
        }
        let shouldClearSuggestions = !searchSuggestionsMatchCurrentQuery
        retainedSearchSuggestions = []
        self.requestedSearchSuggestionQuery = nil
        if shouldClearSuggestions {
            searchManager.clearSuggestions()
            searchSuggestionSourceQuery = nil
        }
        rebuildSuggestionSnapshot()
    }

    private var normalizedCurrentQuery: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchSuggestionsMatchCurrentQuery: Bool {
        searchSuggestionSourceQuery == normalizedCurrentQuery
    }

    private func matchingExtensionSuggestions(
        showsAllWhenEmpty: Bool
    ) -> [SearchManager.SearchSuggestion] {
        let normalizedQuery = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
        return availableExtensionActions.compactMap { action in
            let title = action.title.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            let matches = normalizedQuery.isEmpty
                ? showsAllWhenEmpty
                : title.localizedStandardContains(normalizedQuery)
                    || "extension".hasPrefix(normalizedQuery)
            guard matches else { return nil }
            return SearchManager.SearchSuggestion(
                text: action.title,
                type: .extensionAction(action)
            )
        }
    }

    private func setCommittedSuggestionLayoutCount(_ count: Int) {
        committedSuggestionLayoutCount = count
    }

    private func handleSearchManagerStateChanged() {
        handleSuggestionsChanged()
        handleSuggestionLoadingChanged()
    }
}
