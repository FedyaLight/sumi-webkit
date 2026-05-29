//
//  FloatingBarView.swift
//  Sumi
//
//

import AppKit
import SwiftUI

struct FloatingBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var searchManager = SearchManager()
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @FocusState private var isSearchFocused: Bool
    @State private var text: String = ""
    @State private var selectedSuggestionIndex: Int = -1
    @State private var hoveredSuggestionIndex: Int? = nil
    @State private var activeSiteSearch: SiteSearchEntry? = nil
    @State private var searchModeConfirmation: FloatingBarSearchModeConfirmation?
    @State private var searchModeConfirmationProgress: CGFloat = 1
    @State private var floatingBarCardView: NSView?
    @State private var outsideClickMonitor = ChromeLocalEventMonitor()
    @State private var searchDebouncer = MainActorDebouncedTask()
    @State private var suppressNextTextSearch = false
    @State private var isWaitingForSearchDebounce = false
    @State private var committedSuggestionLayoutCount = 0
    @State private var isSuggestionPreviewActive = false
    @State private var suggestionPreviewRestorationText: String?
    @State private var searchFocusRequestID = 0
    @State private var searchFocusSelectAll = false

    private var siteSearchMatch: SiteSearchEntry? {
        guard activeSiteSearch == nil else { return nil }
        return SiteSearchEntry.match(for: text, in: sumiSettings.siteSearchEntries)
    }

    private var visibleSuggestions: [SearchManager.SearchSuggestion] {
        if activeSiteSearch != nil {
            return searchManager.suggestions.filter {
                if case .search = $0.type { return true }
                return false
            }
        }
        return searchManager.suggestions
    }

    private var urlBarPlaceholderString: String {
        if let site = activeSiteSearch {
            return "Search \(site.name)..."
        }
        return "Search..."
    }

    private var isWaitingForSuggestions: Bool {
        FloatingBarLayoutPolicy.shouldWaitForSuggestionLayout(
            isDebouncing: isWaitingForSearchDebounce,
            isLoading: searchManager.isLoadingSuggestions,
            visibleLayoutCount: visibleSuggestionLayoutCount
        )
    }

    private var visibleSuggestionLayoutCount: Int {
        FloatingBarLayoutPolicy.layoutCount(forVisibleCount: visibleSuggestions.count)
    }

    private var suggestionLayoutCount: Int {
        committedSuggestionLayoutCount
    }

    private var shouldShowEmptyStateSuggestions: Bool {
        windowState.floatingBarPresentationReason == .splitTabPicker
            || sumiSettings.floatingBarEmptyStateMode == .topLinks
    }

    private var chromeContentAnimation: Animation? {
        FloatingBarMotionPolicy.chromeContentAnimation(for: motionMode)
    }

    private var microAffordanceAnimation: Animation? {
        FloatingBarMotionPolicy.microAffordanceAnimation(for: motionMode)
    }

    private var motionMode: FloatingBarMotionPolicy.Mode {
        FloatingBarMotionPolicy.mode(reduceMotion: accessibilityReduceMotion)
    }

    var body: some View {
        GeometryReader { proxy in
            floatingBarBody(
                effectiveFloatingBarWidth: FloatingBarLayoutPolicy.effectiveWidth(
                    availableWindowWidth: availableWindowWidth(from: proxy.size.width)
                )
            )
        }
    }

    @ViewBuilder
    private func floatingBarBody(effectiveFloatingBarWidth: CGFloat) -> some View {
        let isVisible = windowState.isFloatingBarVisible
        let tokens = self.tokens
        let urlBarPlaceholder = urlBarPlaceholderString
        let textFieldFont = Font.system(size: 13, weight: .semibold)
        let siteSearchMatchID = siteSearchMatch?.id

        ZStack {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack {
                        VStack(alignment: .center, spacing: 0) {
                            HStack(spacing: 15) {
                                Image(
                                    systemName: activeSiteSearch != nil
                                        ? "magnifyingglass"
                                        : isLikelyURL(text)
                                            ? "globe" : "magnifyingglass"
                                )
                                .id(activeSiteSearch != nil ? "magnifyingglass" : isLikelyURL(text) ? "globe" : "magnifyingglass")
                                .transition(FloatingBarMotionPolicy.chromeElementTransition(for: motionMode))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(tokens.secondaryText)
                                .frame(width: 15)

                                if let site = activeSiteSearch {
                                    Text(site.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(
                                            ThemeContrastResolver.contrastingShade(
                                                of: site.color,
                                                targetRatio: 4.5,
                                                minimumBlend: 0.68
                                            ) ?? ThemeContrastResolver.preferredForeground(on: site.color)
                                        )
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .background(site.color)
                                        .clipShape(Capsule())
                                        .transition(
                                            FloatingBarMotionPolicy.chromeElementTransition(for: motionMode)
                                        )
                                }

                                ZStack(alignment: .trailing) {
                                    ZStack(alignment: .leading) {
                                        if text.isEmpty {
                                            Text(urlBarPlaceholder)
                                                .font(textFieldFont)
                                                .foregroundStyle(tokens.secondaryText)
                                                .allowsHitTesting(false)
                                        }
                                        FloatingBarInlineCompletionTextField(
                                            text: $text,
                                            isFocused: $isSearchFocused,
                                            font: .systemFont(ofSize: 13, weight: .semibold),
                                            primaryColor: NSColor(tokens.primaryText),
                                            hidesCaret: isSuggestionPreviewActive,
                                            movesInsertionPointToEnd: isSuggestionPreviewActive,
                                            focusRequestID: searchFocusRequestID,
                                            focusSelectAll: searchFocusSelectAll,
                                            onBeginEditing: {
                                                commitSuggestionPreviewForEditing()
                                            },
                                            onTab: {
                                                if isSuggestionPreviewActive {
                                                    commitSuggestionPreviewForEditing()
                                                    return true
                                                }
                                                if let match = siteSearchMatch, activeSiteSearch == nil {
                                                    enterSiteSearch(match)
                                                    return true
                                                }
                                                return false
                                            },
                                            onReturn: {
                                                handleReturn()
                                            },
                                            onMoveSelection: { direction in
                                                navigateSuggestions(direction: direction)
                                            },
                                            onEscape: {
                                                if activeSiteSearch != nil {
                                                    updateWithMotion(chromeContentAnimation) {
                                                        activeSiteSearch = nil
                                                    }
                                                } else {
                                                    browserManager.dismissFloatingBar(in: windowState, preserveDraft: true)
                                                }
                                            },
                                            onDeleteAtEmptySiteSearch: {
                                                guard activeSiteSearch != nil && text.isEmpty else { return false }
                                                updateWithMotion(chromeContentAnimation) {
                                                    activeSiteSearch = nil
                                                }
                                                return true
                                            }
                                        )
                                            .tint(tokens.primaryText)
                                            .accessibilityIdentifier("floating-bar-input")
                                            .accessibilityLabel("Search")
                                            .onChange(of: text) { _, newValue in
                                                // Defer floating bar / window session writes so `BrowserWindowState` is not mutated during SwiftUI view updates.
                                                Task { @MainActor in
                                                    browserManager.updateFloatingBarDraft(in: windowState, text: newValue)
                                                    guard !suppressNextTextSearch else {
                                                        suppressNextTextSearch = false
                                                        return
                                                    }
                                                    commitSuggestionPreviewForEditing()
                                                    scheduleSearchSuggestions(for: newValue)
                                                    selectedSuggestionIndex = -1
                                                }
                                            }
                                    }

                                    if activeSiteSearch == nil, let match = siteSearchMatch {
                                        HStack(spacing: 6) {
                                            Text("Search \(match.name)")
                                                .font(textFieldFont)
                                                .foregroundStyle(tokens.secondaryText)
                                                .lineLimit(1)
                                                .truncationMode(.tail)

                                            Text("Tab")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(tokens.secondaryText)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(tokens.floatingBarChipBackground)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .stroke(tokens.separator, lineWidth: 0.5)
                                                )
                                        }
                                        .allowsHitTesting(false)
                                        .transition(
                                            FloatingBarMotionPolicy.chromeElementTransition(for: motionMode)
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
                                .animation(microAffordanceAnimation, value: siteSearchMatchID)
                            }
                            .frame(height: FloatingBarLayoutPolicy.inputRowHeight)
                            .padding(.vertical, FloatingBarLayoutPolicy.inputRowVerticalPadding)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusSearchField(selectAll: false)
                            }

                            FloatingBarResultsPanelView(
                                tokens: tokens,
                                suggestions: visibleSuggestions,
                                layoutSuggestionCount: suggestionLayoutCount,
                                selectedIndex: $selectedSuggestionIndex,
                                hoveredIndex: $hoveredSuggestionIndex,
                                onSelect: { suggestion in
                                    selectSuggestion(suggestion)
                                },
                                onDeleteHistoryEntry: { entry in
                                    deleteHistoryEntry(entry)
                                }
                            )
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .frame(width: effectiveFloatingBarWidth)
                        .background {
                            if isVisible {
                                MouseEventShieldView(
                                    suppressesUnderlyingWebContentHover: true,
                                    cursorPolicy: .none
                                )
                            }
                        }
                        .background(tokens.floatingBarBackground)
                        .clipShape(.rect(cornerRadius: 26))
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(
                                    tokens.separator.opacity(
                                        accessibilityReduceTransparency ? 0.95 : 0.72
                                    ),
                                    lineWidth: accessibilityReduceTransparency ? 1.15 : 1
                                )
                        }
                        .overlay {
                            if let confirmation = searchModeConfirmation {
                                FloatingBarSearchModeConfirmationView(
                                    confirmation: confirmation,
                                    progress: searchModeConfirmationProgress
                                )
                                    .allowsHitTesting(false)
                            }
                        }
                        .modifier(
                            FloatingBarLocalVignetteModifier(
                                chromeScheme: themeContext.targetChromeColorScheme,
                                reduceTransparency: accessibilityReduceTransparency
                            )
                        )
                        .background(
                            FloatingBarCardBoundsReader { view in
                                if floatingBarCardView !== view {
                                    floatingBarCardView = view
                                }
                            }
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("floating-bar")
                        .padding(.horizontal, FloatingBarLayoutPolicy.horizontalVignetteOutset)
                        .padding(.vertical, FloatingBarLayoutPolicy.verticalVignetteOutset)
                        Spacer()
                    }
                    .frame(
                        width: effectiveFloatingBarWidth
                            + FloatingBarLayoutPolicy.horizontalVignetteOutset * 2,
                        height: FloatingBarLayoutPolicy.contentHeight
                            + FloatingBarLayoutPolicy.verticalVignetteOutset * 2
                    )

                    Spacer()
                }
                Spacer()
            }

        }
        .allowsHitTesting(isVisible)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            if windowState.isFloatingBarVisible {
                handleVisibilityChanged(true)
            }
        }
        .onChange(of: windowState.isFloatingBarVisible) { _, newVisible in
            handleVisibilityChanged(newVisible)
        }
        .onDisappear {
            searchDebouncer.cancel()
            removeOutsideClickMonitor()
        }
        .onChange(of: browserManager.currentProfile?.id) { _, _ in
            if windowState.isFloatingBarVisible {
                searchManager.updateProfileContext()
                searchManager.clearSuggestions()
            }
        }
        .onChange(of: searchManager.suggestions.count) { _, _ in
            let count = visibleSuggestions.count
            if count == 0 {
                selectedSuggestionIndex = -1
            } else if selectedSuggestionIndex >= count {
                selectedSuggestionIndex = count - 1
            }
            commitSuggestionLayoutCountIfReady()
        }
        .onChange(of: searchManager.isLoadingSuggestions) { _, isLoading in
            if !isLoading {
                commitSuggestionLayoutCount()
            }
        }
        .onChange(of: activeSiteSearch != nil) { _, _ in
            commitSuggestionLayoutCountIfReady()
        }
        .onChange(of: windowState.floatingBarDraftText) { _, newValue in
            if isVisible, newValue != text {
                text = newValue
                focusSearchField(selectAll: false)
            }
        }
        .onChange(of: sumiSettings.floatingBarEmptyStateMode) { _, _ in
            refreshEmptyStateSuggestionsIfNeeded()
        }
        .onChange(of: windowState.floatingBarPresentationReason) { _, _ in
            refreshEmptyStateSuggestionsIfNeeded()
        }
    }

    private func availableWindowWidth(from layoutWidth: CGFloat) -> CGFloat {
        if let contentWidth = windowState.window?.contentView?.bounds.width,
           contentWidth > 0
        {
            return contentWidth
        }
        if layoutWidth > 0 {
            return layoutWidth
        }
        return windowState.window?.frame.width ?? 0
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private func scheduleSearchSuggestions(for query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchDebouncer.cancel()
            setWaitingForSearchDebounce(false)
            refreshEmptyStateSuggestionsIfNeeded()
            return
        }

        setWaitingForSearchDebounce(true)
        searchDebouncer.schedule(delayNanoseconds: 160_000_000) {
            setWaitingForSearchDebounce(false)
            searchManager.searchSuggestions(for: trimmedQuery)
        }
    }

    private func handleVisibilityChanged(_ newVisible: Bool) {
        if newVisible {
            installOutsideClickMonitorIfNeeded()
            searchManager.setTabManager(browserManager.tabManager)
            searchManager.setHistoryManager(browserManager.historyManager)
            searchManager.setBookmarkManager(browserManager.bookmarkManager)
            searchManager.updateProfileContext()

            text = windowState.floatingBarDraftText
            refreshEmptyStateSuggestionsIfNeeded()

            DispatchQueue.main.async {
                focusSearchField(selectAll: !text.isEmpty)
            }
        } else {
            searchDebouncer.cancel()
            isWaitingForSearchDebounce = false
            removeOutsideClickMonitor()
            isSearchFocused = false
            searchManager.clearSuggestions()
            text = ""
            activeSiteSearch = nil
            searchModeConfirmation = nil
            searchModeConfirmationProgress = 1
            selectedSuggestionIndex = -1
            committedSuggestionLayoutCount = 0
            isSuggestionPreviewActive = false
            suggestionPreviewRestorationText = nil
            suppressNextTextSearch = false
        }
    }

    private func refreshEmptyStateSuggestionsIfNeeded() {
        guard windowState.isFloatingBarVisible,
              activeSiteSearch == nil,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        searchDebouncer.cancel()
        setWaitingForSearchDebounce(false)
        if windowState.floatingBarPresentationReason == .splitTabPicker {
            setCommittedSuggestionLayoutCount(
                FloatingBarLayoutPolicy.suggestionsVisibleRowLimit,
                animated: false
            )
            searchManager.showActiveTabSuggestions(for: windowState)
        } else if sumiSettings.floatingBarEmptyStateMode == .topLinks {
            setCommittedSuggestionLayoutCount(
                FloatingBarLayoutPolicy.suggestionsVisibleRowLimit,
                animated: false
            )
            searchManager.showTopLinkSuggestions(
                limit: FloatingBarLayoutPolicy.suggestionsVisibleRowLimit
            )
        } else {
            searchManager.clearSuggestions()
            setCommittedSuggestionLayoutCount(0, animated: true)
        }
    }

    private func setWaitingForSearchDebounce(_ isWaiting: Bool) {
        updateWithoutMotion {
            isWaitingForSearchDebounce = isWaiting
        }
    }

    private func commitSuggestionLayoutCountIfReady() {
        guard !isWaitingForSuggestions else { return }
        commitSuggestionLayoutCount()
    }

    private func commitSuggestionLayoutCount() {
        let nextCount = visibleSuggestionLayoutCount
        guard committedSuggestionLayoutCount != nextCount else { return }
        setCommittedSuggestionLayoutCount(
            nextCount,
            animated: chromeContentAnimation != nil
        )
    }

    private func setCommittedSuggestionLayoutCount(_ count: Int, animated: Bool) {
        updateWithMotion(animated ? chromeContentAnimation : nil) {
            committedSuggestionLayoutCount = count
        }
    }

    private func focusSearchField(selectAll: Bool) {
        isSearchFocused = true
        searchFocusSelectAll = selectAll
        searchFocusRequestID &+= 1
    }

    private func enterSiteSearch(_ site: SiteSearchEntry) {
        updateWithMotion(chromeContentAnimation) {
            activeSiteSearch = site
            text = ""
        }
        triggerSearchModeConfirmation(color: site.color)
    }

    private func triggerSearchModeConfirmation(color: Color) {
        guard let animation = FloatingBarMotionPolicy.searchModeConfirmationAnimation(for: motionMode),
              let lifetimeNanoseconds = FloatingBarMotionPolicy.searchModeConfirmationLifetimeNanoseconds(for: motionMode)
        else { return }

        let confirmation = FloatingBarSearchModeConfirmation(color: color)
        searchModeConfirmation = confirmation
        searchModeConfirmationProgress = 0

        withAnimation(animation) {
            searchModeConfirmationProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: lifetimeNanoseconds)
            if searchModeConfirmation?.id == confirmation.id {
                searchModeConfirmation = nil
            }
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

    private func deleteHistoryEntry(_ entry: HistoryListItem) {
        Task { @MainActor in
            if let visitID = entry.visitID {
                await browserManager.historyManager.delete(query: .visits([visitID]))
            } else {
                await browserManager.historyManager.delete(query: .domainFilter([entry.siteDomain ?? entry.domain]))
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                refreshEmptyStateSuggestionsIfNeeded()
            } else {
                searchManager.searchSuggestions(for: trimmed)
            }
        }
    }

    private func completionText(for suggestion: SearchManager.SearchSuggestion) -> String {
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

    private func commitSuggestionPreviewForEditing() {
        isSuggestionPreviewActive = false
        suggestionPreviewRestorationText = nil
    }

    private func handleReturn() {
        if let site = activeSiteSearch {
            let query: String
            if selectedSuggestionIndex >= 0 && selectedSuggestionIndex < visibleSuggestions.count {
                query = visibleSuggestions[selectedSuggestionIndex].text
            } else {
                query = text
            }
            guard !query.isEmpty else { return }
            let navigateURL = resolvedSiteSearchURL(site: site, query: query).absoluteString
            let navigatesCurrentTab = windowState.floatingBarDraftNavigatesCurrentTab
                && browserManager.activePageTab(for: windowState) != nil
            text = ""
            activeSiteSearch = nil
            selectedSuggestionIndex = -1
            DispatchQueue.main.async {
                browserManager.commitFloatingBarNavigation(
                    to: navigateURL,
                    in: windowState,
                    navigatesCurrentTab: navigatesCurrentTab
                )
            }
            return
        }

        if selectedSuggestionIndex >= 0
            && selectedSuggestionIndex < visibleSuggestions.count
        {
            let suggestion = visibleSuggestions[selectedSuggestionIndex]
            selectSuggestion(suggestion)
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let newSuggestion = SearchManager.SearchSuggestion(
                text: trimmed,
                type: isLikelyURL(trimmed) ? .url : .search
            )
            selectSuggestion(newSuggestion)
        }
    }

    private func selectSuggestion(_ suggestion: SearchManager.SearchSuggestion)
    {
        let navigatesCurrentTab = windowState.floatingBarDraftNavigatesCurrentTab
            && browserManager.activePageTab(for: windowState) != nil
        text = ""
        activeSiteSearch = nil
        selectedSuggestionIndex = -1
        DispatchQueue.main.async {
            browserManager.commitFloatingBarSuggestion(
                suggestion,
                in: windowState,
                navigatesCurrentTab: navigatesCurrentTab
            )
        }
    }

    private func resolvedSiteSearchURL(site: SiteSearchEntry, query: String) -> URL {
        if let url = site.searchURL(for: query) {
            return url
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = site.domain
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url ?? URL(string: "https://\(site.domain)")!
    }

    private func navigateSuggestions(direction: Int) {
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

    private func installOutsideClickMonitorIfNeeded() {
        guard !outsideClickMonitor.isInstalled else { return }
        outsideClickMonitor.install(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            FloatingBarOutsideClickRouting.monitorResult(
                for: event,
                isFloatingBarVisible: windowState.isFloatingBarVisible,
                cardView: floatingBarCardView
            ) {
                // Close asynchronously and return the original event so sidebar/browser chrome handles this click.
                DispatchQueue.main.async {
                    windowState.window?.makeFirstResponder(nil)
                    isSearchFocused = false
                    browserManager.dismissFloatingBar(in: windowState, preserveDraft: true)
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        outsideClickMonitor.remove()
    }

}

private struct FloatingBarInlineCompletionTextField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let font: NSFont
    let primaryColor: NSColor
    let hidesCaret: Bool
    let movesInsertionPointToEnd: Bool
    let focusRequestID: Int
    let focusSelectAll: Bool
    let onBeginEditing: () -> Void
    let onTab: () -> Bool
    let onReturn: () -> Void
    let onMoveSelection: (Int) -> Void
    let onEscape: () -> Void
    let onDeleteAtEmptySiteSearch: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> FloatingBarInlineCompletionTextFieldView {
        let view = FloatingBarInlineCompletionTextFieldView()
        view.textField.delegate = context.coordinator
        view.textField.onBeginEditing = onBeginEditing
        context.coordinator.configure(
            onBeginEditing: onBeginEditing,
            onTab: onTab,
            onReturn: onReturn,
            onMoveSelection: onMoveSelection,
            onEscape: onEscape,
            onDeleteAtEmptySiteSearch: onDeleteAtEmptySiteSearch
        )
        update(view, context: context)
        return view
    }

    func updateNSView(_ nsView: FloatingBarInlineCompletionTextFieldView, context: Context) {
        nsView.textField.delegate = context.coordinator
        nsView.textField.onBeginEditing = onBeginEditing
        context.coordinator.configure(
            onBeginEditing: onBeginEditing,
            onTab: onTab,
            onReturn: onReturn,
            onMoveSelection: onMoveSelection,
            onEscape: onEscape,
            onDeleteAtEmptySiteSearch: onDeleteAtEmptySiteSearch
        )
        update(nsView, context: context)
    }

    private func update(_ nsView: FloatingBarInlineCompletionTextFieldView, context _: Context) {
        nsView.configure(
            text: text,
            font: font,
            primaryColor: primaryColor,
            hidesCaret: hidesCaret,
            movesInsertionPointToEnd: movesInsertionPointToEnd
        )

        nsView.wantsTextFocus = isFocused.wrappedValue
        nsView.handleFocusRequest(id: focusRequestID, selectAll: focusSelectAll)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private var onBeginEditing: () -> Void = {}
        private var onTab: () -> Bool = { false }
        private var onReturn: () -> Void = {}
        private var onMoveSelection: (Int) -> Void = { _ in }
        private var onEscape: () -> Void = {}
        private var onDeleteAtEmptySiteSearch: () -> Bool = { false }

        init(text: Binding<String>) {
            _text = text
        }

        func configure(
            onBeginEditing: @escaping () -> Void,
            onTab: @escaping () -> Bool,
            onReturn: @escaping () -> Void,
            onMoveSelection: @escaping (Int) -> Void,
            onEscape: @escaping () -> Void,
            onDeleteAtEmptySiteSearch: @escaping () -> Bool
        ) {
            self.onBeginEditing = onBeginEditing
            self.onTab = onTab
            self.onReturn = onReturn
            self.onMoveSelection = onMoveSelection
            self.onEscape = onEscape
            self.onDeleteAtEmptySiteSearch = onDeleteAtEmptySiteSearch
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            onBeginEditing()
            text = textField.stringValue
        }

        func control(
            _: NSControl,
            textView _: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                onMoveSelection(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                onMoveSelection(1)
                return true
            case #selector(NSResponder.moveRight(_:)):
                onBeginEditing()
                return false
            case #selector(NSResponder.moveLeft(_:)):
                onBeginEditing()
                return false
            case #selector(NSResponder.insertTab(_:)):
                return onTab()
            case #selector(NSResponder.insertNewline(_:)):
                onReturn()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onEscape()
                return true
            case #selector(NSResponder.deleteBackward(_:)),
                 #selector(NSResponder.deleteForward(_:)):
                return onDeleteAtEmptySiteSearch()
            default:
                return false
            }
        }
    }
}

private final class FloatingBarInlineCompletionTextFieldView: NSView {
    let textField = FloatingBarInlineCompletionNSTextField()
    var wantsTextFocus = false
    private var handledFocusRequestID = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusTextFieldIfNeeded()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byClipping
        textField.maximumNumberOfLines = 1
        textField.usesSingleLineMode = true
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.heightAnchor.constraint(equalTo: heightAnchor)
        ])
    }

    func configure(
        text: String,
        font: NSFont,
        primaryColor: NSColor,
        hidesCaret: Bool,
        movesInsertionPointToEnd: Bool
    ) {
        textField.font = font
        textField.textColor = primaryColor
        textField.normalTextColor = primaryColor
        textField.hidesCaret = hidesCaret

        textField.applyText(text, moveInsertionPointToEnd: movesInsertionPointToEnd)
    }

    func focusTextFieldIfNeeded() {
        guard wantsTextFocus, let window else { return }
        if window.firstResponder !== textField,
           window.firstResponder !== textField.currentEditor()
        {
            window.makeFirstResponder(textField)
        }
    }

    func handleFocusRequest(id: Int, selectAll: Bool) {
        guard id != handledFocusRequestID else { return }
        handledFocusRequestID = id
        focusTextField(selectAll: selectAll, remainingRetries: 4)
    }

    private func focusTextField(selectAll: Bool, remainingRetries: Int) {
        guard remainingRetries >= 0 else { return }
        guard let window else {
            DispatchQueue.main.async { [weak self] in
                self?.focusTextField(selectAll: selectAll, remainingRetries: remainingRetries - 1)
            }
            return
        }

        window.makeFirstResponder(textField)
        if selectAll {
            textField.selectText(nil)
        }

        if window.firstResponder !== textField.currentEditor(),
           window.firstResponder !== textField
        {
            DispatchQueue.main.async { [weak self] in
                self?.focusTextField(selectAll: selectAll, remainingRetries: remainingRetries - 1)
            }
        }
    }
}

private final class FloatingBarInlineCompletionNSTextField: NSTextField {
    var onBeginEditing: (() -> Void)?
    var normalTextColor: NSColor = .labelColor
    private let caretColor: NSColor = .systemBlue
    var hidesCaret: Bool = false {
        didSet {
            updateFieldEditorCaret()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onBeginEditing?()
        hidesCaret = false
        textColor = normalTextColor
        moveInsertionPointToEnd()
        super.mouseDown(with: event)
        updateFieldEditorCaret()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        updateFieldEditorCaret()
        return result
    }

    private func updateFieldEditorCaret() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = hidesCaret ? .clear : caretColor
    }

    func applyText(_ text: String, moveInsertionPointToEnd: Bool) {
        if let editor = currentEditor() as? NSTextView {
            if editor.string != text {
                editor.string = text
            }
            stringValue = text
            if moveInsertionPointToEnd {
                let end = (text as NSString).length
                editor.setSelectedRange(NSRange(location: end, length: 0))
            }
            updateFieldEditorCaret()
            return
        }

        if stringValue != text {
            stringValue = text
        }
    }

    private func moveInsertionPointToEnd() {
        guard let editor = currentEditor() as? NSTextView else { return }
        let end = (editor.string as NSString).length
        editor.setSelectedRange(NSRange(location: end, length: 0))
    }
}

enum FloatingBarOutsideClickRouting {
    @MainActor
    static func monitorResult(
        for event: NSEvent,
        isFloatingBarVisible: Bool,
        cardView: NSView?,
        onOutsideClick: () -> Void
    ) -> NSEvent? {
        monitorResult(
            for: event,
            isFloatingBarVisible: isFloatingBarVisible,
            isEventInsideCard: isEventInsideCard(event, cardView: cardView),
            onOutsideClick: onOutsideClick
        )
    }

    static func monitorResult(
        for event: NSEvent,
        isFloatingBarVisible: Bool,
        isEventInsideCard: Bool,
        onOutsideClick: () -> Void
    ) -> NSEvent? {
        guard isFloatingBarVisible else { return event }
        guard !isEventInsideCard else { return event }

        onOutsideClick()
        return event
    }

    @MainActor
    static func isEventInsideCard(_ event: NSEvent, cardView: NSView?) -> Bool {
        guard let cardView,
              let eventWindow = event.window ?? NSApp.window(withWindowNumber: event.windowNumber),
              isLocationInsideCard(
                event.locationInWindow,
                eventWindow: eventWindow,
                cardView: cardView
              )
        else { return false }

        return true
    }

    @MainActor
    static func isLocationInsideCard(
        _ locationInWindow: NSPoint,
        eventWindow: NSWindow,
        cardView: NSView?
    ) -> Bool {
        guard let cardView,
              cardView.window === eventWindow
        else { return false }

        return isLocationInsideCard(locationInWindow, cardView: cardView)
    }

    @MainActor
    static func isLocationInsideCard(
        _ locationInWindow: NSPoint,
        cardView: NSView?
    ) -> Bool {
        guard let cardView else { return false }
        let localPoint = cardView.convert(locationInWindow, from: nil)
        return cardView.bounds.contains(localPoint)
    }
}

private final class FloatingBarCardBoundsProbeView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct FloatingBarCardBoundsReader: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = FloatingBarCardBoundsProbeView()
        DispatchQueue.main.async {
            onResolve(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView)
        }
    }
}
