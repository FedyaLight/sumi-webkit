import Observation
import SwiftUI

@Observable
@MainActor
final class FloatingBarSearchSessionOwner {
    let searchManager: SearchManager
    var text = ""
    var selectedSuggestionIndex = -1
    var hoveredSuggestionIndex: Int?
    var activeSiteSearch: SumiSearchEngine?
    var isWaitingForSearchDebounce = false
    var committedSuggestionLayoutCount = 0
    var isSuggestionPreviewActive = false

    private var searchDebouncer = MainActorDebouncedTask()
    private var suppressNextTextSearch = false
    private var suggestionPreviewRestorationText: String?

    init(searchManager: SearchManager = SearchManager()) {
        self.searchManager = searchManager
    }

    var visibleSuggestions: [SearchManager.SearchSuggestion] {
        if activeSiteSearch != nil {
            return searchManager.suggestions.filter {
                if case .search = $0.type { return true }
                return false
            }
        }
        return searchManager.suggestions
    }

    var visibleSuggestionLayoutCount: Int {
        FloatingBarLayoutPolicy.layoutCount(forVisibleCount: visibleSuggestions.count)
    }

    var suggestionLayoutCount: Int {
        committedSuggestionLayoutCount
    }

    func siteSearchMatch(in searchEngines: [SumiSearchEngine]) -> SumiSearchEngine? {
        guard activeSiteSearch == nil else { return nil }
        return SumiSearchEngine.match(for: text, in: searchEngines)
    }

    func urlBarPlaceholderString() -> String {
        if let site = activeSiteSearch {
            return "Search \(site.name)..."
        }
        return "Search..."
    }

    func isWaitingForSuggestions() -> Bool {
        FloatingBarLayoutPolicy.shouldWaitForSuggestionLayout(
            isDebouncing: isWaitingForSearchDebounce,
            isLoading: searchManager.isLoadingSuggestions,
            visibleLayoutCount: visibleSuggestionLayoutCount
        )
    }

    func handleTextChanged(
        _ newValue: String,
        isFloatingBarVisible: Bool,
        presentationReason: FloatingBarPresentationReason,
        emptyStateMode: FloatingBarEmptyStateMode,
        windowState: BrowserWindowState,
        chromeContentAnimation: Animation?
    ) {
        guard !suppressNextTextSearch else {
            suppressNextTextSearch = false
            return
        }

        commitSuggestionPreviewForEditing()
        scheduleSearchSuggestions(
            for: newValue,
            isFloatingBarVisible: isFloatingBarVisible,
            presentationReason: presentationReason,
            emptyStateMode: emptyStateMode,
            windowState: windowState,
            chromeContentAnimation: chromeContentAnimation
        )
        selectedSuggestionIndex = -1
    }

    func scheduleSearchSuggestions(
        for query: String,
        isFloatingBarVisible: Bool,
        presentationReason: FloatingBarPresentationReason,
        emptyStateMode: FloatingBarEmptyStateMode,
        windowState: BrowserWindowState,
        chromeContentAnimation: Animation?
    ) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchDebouncer.cancel()
            setWaitingForSearchDebounce(false)
            refreshEmptyStateSuggestionsIfNeeded(
                isFloatingBarVisible: isFloatingBarVisible,
                presentationReason: presentationReason,
                emptyStateMode: emptyStateMode,
                windowState: windowState,
                chromeContentAnimation: chromeContentAnimation
            )
            return
        }

        setWaitingForSearchDebounce(true)
        searchDebouncer.schedule(delayNanoseconds: 160_000_000) { [weak self] in
            guard let self else { return }
            self.setWaitingForSearchDebounce(false)
            self.searchManager.searchSuggestions(for: trimmedQuery)
        }
    }

    func refreshEmptyStateSuggestionsIfNeeded(
        isFloatingBarVisible: Bool,
        presentationReason: FloatingBarPresentationReason,
        emptyStateMode: FloatingBarEmptyStateMode,
        windowState: BrowserWindowState,
        chromeContentAnimation: Animation?
    ) {
        guard isFloatingBarVisible,
              activeSiteSearch == nil,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        searchDebouncer.cancel()
        setWaitingForSearchDebounce(false)
        if presentationReason == .splitTabPicker {
            setCommittedSuggestionLayoutCount(
                FloatingBarLayoutPolicy.suggestionsVisibleRowLimit,
                animated: false,
                chromeContentAnimation: chromeContentAnimation
            )
            searchManager.showActiveTabSuggestions(for: windowState)
        } else if emptyStateMode == .topLinks {
            setCommittedSuggestionLayoutCount(
                FloatingBarLayoutPolicy.suggestionsVisibleRowLimit,
                animated: false,
                chromeContentAnimation: chromeContentAnimation
            )
            searchManager.showTopLinkSuggestions(
                limit: FloatingBarLayoutPolicy.suggestionsVisibleRowLimit
            )
        } else {
            searchManager.clearSuggestions()
            setCommittedSuggestionLayoutCount(
                0,
                animated: true,
                chromeContentAnimation: chromeContentAnimation
            )
        }
    }

    func handleProfileContextChanged(isFloatingBarVisible: Bool) {
        guard isFloatingBarVisible else { return }
        searchManager.updateProfileContext()
        searchManager.clearSuggestions()
    }

    func handleSuggestionsChanged(chromeContentAnimation: Animation?) {
        let count = visibleSuggestions.count
        if count == 0 {
            selectedSuggestionIndex = -1
        } else if selectedSuggestionIndex >= count {
            selectedSuggestionIndex = count - 1
        }
        commitSuggestionLayoutCountIfReady(chromeContentAnimation: chromeContentAnimation)
    }

    func handleSuggestionLoadingChanged(
        isLoading: Bool,
        chromeContentAnimation: Animation?
    ) {
        if !isLoading {
            commitSuggestionLayoutCount(chromeContentAnimation: chromeContentAnimation)
        }
    }

    func commitSuggestionLayoutCountIfReady(chromeContentAnimation: Animation?) {
        guard !isWaitingForSuggestions() else { return }
        commitSuggestionLayoutCount(chromeContentAnimation: chromeContentAnimation)
    }

    func commitSuggestionLayoutCount(chromeContentAnimation: Animation?) {
        let nextCount = visibleSuggestionLayoutCount
        guard committedSuggestionLayoutCount != nextCount else { return }
        setCommittedSuggestionLayoutCount(
            nextCount,
            animated: chromeContentAnimation != nil,
            chromeContentAnimation: chromeContentAnimation
        )
    }

    func enterSiteSearch(_ site: SumiSearchEngine, chromeContentAnimation: Animation?) {
        updateWithMotion(chromeContentAnimation) {
            activeSiteSearch = site
            text = ""
        }
    }

    func clearActiveSiteSearch(chromeContentAnimation: Animation?) {
        updateWithMotion(chromeContentAnimation) {
            activeSiteSearch = nil
        }
    }

    func commitSuggestionPreviewForEditing() {
        isSuggestionPreviewActive = false
        suggestionPreviewRestorationText = nil
    }

    func completionText(for suggestion: SearchManager.SearchSuggestion) -> String {
        switch suggestion.type {
        case .search:
            return suggestion.text
        case .url:
            return suggestion.text
        case .history(let entry):
            return entry.url.absoluteString
        case .bookmark(let bookmark):
            return bookmark.url.absoluteString
        case .tab(let tab):
            return tab.url.absoluteString
        }
    }

    func navigateSuggestions(direction: Int) {
        let maxIndex = visibleSuggestions.count - 1
        guard maxIndex >= 0 else {
            selectedSuggestionIndex = -1
            isSuggestionPreviewActive = false
            suggestionPreviewRestorationText = nil
            return
        }

        let oldIndex = selectedSuggestionIndex
        let newIndex: Int
        if direction > 0 {
            newIndex = min(selectedSuggestionIndex + 1, maxIndex)
        } else {
            newIndex = max(selectedSuggestionIndex - 1, -1)
        }

        guard newIndex != oldIndex else { return }

        if oldIndex == -1, suggestionPreviewRestorationText == nil {
            suggestionPreviewRestorationText = text
        }

        selectedSuggestionIndex = newIndex
        suppressNextTextSearch = true

        if newIndex == -1 {
            text = suggestionPreviewRestorationText ?? text
            isSuggestionPreviewActive = false
            suggestionPreviewRestorationText = nil
        } else {
            text = completionText(for: visibleSuggestions[newIndex])
            isSuggestionPreviewActive = true
        }
    }

    func resetForHiddenBar() {
        searchDebouncer.cancel()
        isWaitingForSearchDebounce = false
        searchManager.clearSuggestions()
        text = ""
        activeSiteSearch = nil
        selectedSuggestionIndex = -1
        hoveredSuggestionIndex = nil
        committedSuggestionLayoutCount = 0
        isSuggestionPreviewActive = false
        suggestionPreviewRestorationText = nil
        suppressNextTextSearch = false
    }

    func cancelPendingSearch() {
        searchDebouncer.cancel()
    }

    private func setWaitingForSearchDebounce(_ isWaiting: Bool) {
        updateWithoutMotion {
            isWaitingForSearchDebounce = isWaiting
        }
    }

    private func setCommittedSuggestionLayoutCount(
        _ count: Int,
        animated: Bool,
        chromeContentAnimation: Animation?
    ) {
        updateWithMotion(animated ? chromeContentAnimation : nil) {
            committedSuggestionLayoutCount = count
        }
    }

    private func updateWithMotion(
        _ animation: Animation?,
        _ updates: () -> Void
    ) {
        guard let animation else {
            updateWithoutMotion(updates)
            return
        }

        withAnimation(animation) {
            updates()
        }
    }

    private func updateWithoutMotion(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            updates()
        }
    }
}
