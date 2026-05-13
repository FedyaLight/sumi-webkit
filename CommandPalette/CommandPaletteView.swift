//
//  CommandPaletteView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import AppKit
import SwiftUI

enum CommandPaletteLayoutPolicy {
    static let idealWidth: CGFloat = 765
    static let horizontalPadding: CGFloat = 10
    static let minimumWidth: CGFloat = 200
    static let horizontalVignetteOutset: CGFloat = 56
    static let verticalVignetteOutset: CGFloat = 72
    static let contentHeight: CGFloat = 328
    static let inputRowHeight: CGFloat = 22
    static let inputRowVerticalPadding: CGFloat = 5
    static let suggestionsMaxHeight: CGFloat = 260
    static let suggestionsVisibleRowLimit = 5
    static let suggestionRowMinHeight: CGFloat = 32
    static let suggestionRowHorizontalPadding: CGFloat = 8
    static let suggestionRowVerticalPadding: CGFloat = 10
    static let suggestionRowSpacing: CGFloat = 0

    static var suggestionRowHeight: CGFloat {
        suggestionRowMinHeight + suggestionRowVerticalPadding * 2
    }

    static func suggestionsHeight(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        guard count <= suggestionsVisibleRowLimit else { return suggestionsMaxHeight }
        let visibleCount = count
        let rowHeights = CGFloat(visibleCount) * suggestionRowHeight
        let spacings = CGFloat(max(visibleCount - 1, 0)) * suggestionRowSpacing
        return min(suggestionsMaxHeight, rowHeights + spacings)
    }

    static var panelHeight: CGFloat {
        contentHeight + verticalVignetteOutset * 2
    }

    static func effectiveWidth(availableWindowWidth: CGFloat) -> CGFloat {
        min(
            idealWidth,
            max(minimumWidth, availableWindowWidth - (horizontalPadding * 2))
        )
    }

    static func panelWidth(availableWindowWidth: CGFloat) -> CGFloat {
        effectiveWidth(availableWindowWidth: availableWindowWidth) + horizontalVignetteOutset * 2
    }
}

struct CommandPaletteView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    @State private var searchManager = SearchManager()
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency

    @FocusState private var isSearchFocused: Bool
    @State private var text: String = ""
    @State private var selectedSuggestionIndex: Int = -1
    @State private var hoveredSuggestionIndex: Int? = nil
    @State private var activeSiteSearch: SiteSearchEntry? = nil
    @State private var searchModeScale: CGFloat = 1
    @State private var searchModeGlow: CommandPaletteSearchModeGlow?
    @State private var searchModeGlowProgress: CGFloat = 1
    @State private var paletteCardView: NSView?
    @State private var outsideClickMonitor: Any?
    @State private var searchDebounceTask: Task<Void, Never>?

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

    var body: some View {
        GeometryReader { proxy in
            commandPaletteBody(
                effectiveCommandPaletteWidth: CommandPaletteLayoutPolicy.effectiveWidth(
                    availableWindowWidth: availableWindowWidth(from: proxy.size.width)
                )
            )
        }
    }

    @ViewBuilder
    private func commandPaletteBody(effectiveCommandPaletteWidth: CGFloat) -> some View {
        let isVisible = commandPalette.isVisible
        let tokens = self.tokens
        let urlBarPlaceholder = urlBarPlaceholderString
        let textFieldFont = Font.system(size: 13, weight: .semibold)

        ZStack {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack {
                        VStack(alignment: .center,spacing: 6) {
                            HStack(spacing: 15) {
                                Image(
                                    systemName: activeSiteSearch != nil
                                        ? "magnifyingglass"
                                        : isLikelyURL(text)
                                            ? "globe" : "magnifyingglass"
                                )
                                .id(activeSiteSearch != nil ? "magnifyingglass" : isLikelyURL(text) ? "globe" : "magnifyingglass")
                                .transition(.blur(intensity: 2, scale: 0.6).animation(.smooth(duration: 0.3)))
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
                                            .blur(intensity: 8, scale: 0.6)
                                            .animation(.spring(response: 0.35, dampingFraction: 0.75))
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
                                        TextField("", text: $text)
                                            .accessibilityIdentifier("floating-urlbar-input")
                                            .accessibilityLabel("Search")
                                            .textFieldStyle(.plain)
                                            .font(textFieldFont)
                                            .foregroundStyle(tokens.primaryText)
                                            .tint(tokens.primaryText)
                                            .lineLimit(1)
                                            .focused($isSearchFocused)
                                            .onKeyPress(.tab) {
                                                if let match = siteSearchMatch, activeSiteSearch == nil {
                                                    enterSiteSearch(match)
                                                    return .handled
                                                }
                                                return .ignored
                                            }
                                            .onKeyPress(.return) {
                                                handleReturn()
                                                return .handled
                                            }
                                            .onKeyPress(.upArrow) {
                                                navigateSuggestions(direction: -1)
                                                return .handled
                                            }
                                            .onKeyPress(.downArrow) {
                                                navigateSuggestions(direction: 1)
                                                return .handled
                                            }
                                            .onKeyPress(.escape) {
                                                if activeSiteSearch != nil {
                                                    withAnimation(.smooth(duration: 0.25)) {
                                                        activeSiteSearch = nil
                                                    }
                                                    return .handled
                                                }
                                                commandPalette.close(preserveDraft: true)
                                                return .handled
                                            }
                                            .onKeyPress(.delete) {
                                                if activeSiteSearch != nil && text.isEmpty {
                                                    withAnimation(.smooth(duration: 0.25)) {
                                                        activeSiteSearch = nil
                                                    }
                                                    return .handled
                                                }
                                                return .ignored
                                            }
                                            .onKeyPress(characters: CharacterSet(charactersIn: "\u{7F}")) { _ in
                                                if activeSiteSearch != nil && text.isEmpty {
                                                    withAnimation(.smooth(duration: 0.25)) {
                                                        activeSiteSearch = nil
                                                    }
                                                    return .handled
                                                }
                                                return .ignored
                                            }
                                            .onChange(of: text) { _, newValue in
                                                // Defer palette / window session writes so `BrowserWindowState` is not mutated during SwiftUI view updates.
                                                Task { @MainActor in
                                                    commandPalette.updateDraft(text: newValue)
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
                                                        .fill(tokens.commandPaletteChipBackground)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .stroke(tokens.separator, lineWidth: 0.5)
                                                )
                                        }
                                        .allowsHitTesting(false)
                                        .transition(
                                            .blur(intensity: 4, scale: 0.92)
                                            .animation(.smooth(duration: 0.3))
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
                            }
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: activeSiteSearch != nil)
                            .frame(height: CommandPaletteLayoutPolicy.inputRowHeight)
                            .padding(.vertical, CommandPaletteLayoutPolicy.inputRowVerticalPadding)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusSearchField(selectAll: false)
                            }

                            if !visibleSuggestions.isEmpty {
                                RoundedRectangle(cornerRadius: 100)
                                    .fill(tokens.separator.opacity(0.9))
                                    .frame(height: 0.5)
                                    .frame(maxWidth: .infinity)
                            }

                            if !visibleSuggestions.isEmpty {
                                CommandPaletteSuggestionsListView(
                                    tokens: tokens,
                                    suggestions: visibleSuggestions,
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
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .frame(width: effectiveCommandPaletteWidth)
                        .scaleEffect(searchModeScale)
                        .background {
                            if isVisible {
                                MouseEventShieldView(suppressesUnderlyingWebContentHover: true)
                            }
                        }
                        .background(tokens.commandPaletteBackground)
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
                            if let glow = searchModeGlow {
                                CommandPaletteSearchModeGlowView(
                                    glow: glow,
                                    progress: searchModeGlowProgress
                                )
                                    .allowsHitTesting(false)
                            }
                        }
                        .modifier(
                            CommandPaletteLocalVignetteModifier(
                                chromeScheme: themeContext.targetChromeColorScheme,
                                reduceTransparency: accessibilityReduceTransparency
                            )
                        )
                        .background(
                            CommandPaletteCardBoundsReader { view in
                                if paletteCardView !== view {
                                    paletteCardView = view
                                }
                            }
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("floating-urlbar")
                        .animation(
                            .easeInOut(duration: 0.15),
                            value: searchManager.suggestions.count
                        )
                        .padding(.horizontal, CommandPaletteLayoutPolicy.horizontalVignetteOutset)
                        .padding(.vertical, CommandPaletteLayoutPolicy.verticalVignetteOutset)
                        Spacer()
                    }
                    .frame(
                        width: effectiveCommandPaletteWidth
                            + CommandPaletteLayoutPolicy.horizontalVignetteOutset * 2,
                        height: CommandPaletteLayoutPolicy.contentHeight
                            + CommandPaletteLayoutPolicy.verticalVignetteOutset * 2
                    )

                    Spacer()
                }
                Spacer()
            }

        }
        .allowsHitTesting(isVisible)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            if commandPalette.isVisible {
                handleVisibilityChanged(true)
            }
        }
        .onChange(of: commandPalette.isVisible) { _, newVisible in
            handleVisibilityChanged(newVisible)
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            removeOutsideClickMonitor()
        }
        .onChange(of: browserManager.currentProfile?.id) { _, _ in
            if commandPalette.isVisible {
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
        }
        .animation(.easeInOut(duration: 0.15), value: selectedSuggestionIndex)
        .onChange(of: commandPalette.prefilledText) { _, newValue in
            if isVisible {
                text = newValue
                DispatchQueue.main.async {
                    focusSearchField(selectAll: false)
                }
            }
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
        searchDebounceTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchManager.clearSuggestions()
            return
        }

        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            searchManager.searchSuggestions(for: trimmedQuery)
        }
    }

    private func handleVisibilityChanged(_ newVisible: Bool) {
        if newVisible {
            installOutsideClickMonitorIfNeeded()
            searchManager.setTabManager(browserManager.tabManager)
            searchManager.setHistoryManager(browserManager.historyManager)
            searchManager.updateProfileContext()

            text = commandPalette.prefilledText

            DispatchQueue.main.async {
                focusSearchField(selectAll: true)
            }
        } else {
            searchDebounceTask?.cancel()
            removeOutsideClickMonitor()
            isSearchFocused = false
            searchManager.clearSuggestions()
            text = ""
            activeSiteSearch = nil
            searchModeScale = 1
            searchModeGlow = nil
            searchModeGlowProgress = 1
            selectedSuggestionIndex = -1
        }
    }

    private func focusSearchField(selectAll: Bool) {
        isSearchFocused = true
        guard selectAll else { return }
        DispatchQueue.main.async {
            NSApplication.shared.sendAction(
                #selector(NSText.selectAll(_:)),
                to: nil,
                from: nil
            )
        }
    }

    private func enterSiteSearch(_ site: SiteSearchEntry) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            activeSiteSearch = site
        }
        text = ""
        triggerSearchModeAnimation(color: site.color)
    }

    private func triggerSearchModeAnimation(color: Color) {
        let glow = CommandPaletteSearchModeGlow(color: color)
        searchModeGlow = glow
        searchModeGlowProgress = 0
        searchModeScale = 1

        withAnimation(.easeOut(duration: 0.125)) {
            searchModeScale = 0.98
        }
        withAnimation(.easeOut(duration: 1)) {
            searchModeGlowProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 125_000_000)
            withAnimation(.easeOut(duration: 0.125)) {
                searchModeScale = 1
            }

            try? await Task.sleep(nanoseconds: 875_000_000)
            if searchModeGlow?.id == glow.id {
                searchModeGlow = nil
            }
        }
    }

    // MARK: - Suggestions List Subview
    private struct CommandPaletteSuggestionsListView: View {
        let tokens: ChromeThemeTokens
        let suggestions: [SearchManager.SearchSuggestion]
        @Binding var selectedIndex: Int
        @Binding var hoveredIndex: Int?
        let onSelect: (SearchManager.SearchSuggestion) -> Void
        let onDeleteHistoryEntry: (HistoryListItem) -> Void

        var body: some View {
            let selectedBackground = tokens.accent.opacity(0.58)
            let selectedForeground = ThemeContrastResolver.preferredForeground(on: tokens.accent)
            let selectedChipBackground = selectedForeground.opacity(0.88)
            let selectedChipForeground = ThemeContrastResolver.preferredForeground(on: selectedForeground)
            let shouldScroll = suggestions.count > CommandPaletteLayoutPolicy.suggestionsVisibleRowLimit

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: CommandPaletteLayoutPolicy.suggestionRowSpacing) {
                        ForEach(suggestions.indices, id: \.self) { index in
                            let suggestion = suggestions[index]
                            let isSelected = selectedIndex == index
                            let isHovered = hoveredIndex == index
                            row(
                                for: suggestion,
                                isSelected: isSelected,
                                selectedForeground: selectedForeground,
                                selectedChipBackground: selectedChipBackground,
                                selectedChipForeground: selectedChipForeground
                            )
                                .frame(minHeight: CommandPaletteLayoutPolicy.suggestionRowMinHeight)
                                .padding(.horizontal, CommandPaletteLayoutPolicy.suggestionRowHorizontalPadding)
                                .padding(.vertical, CommandPaletteLayoutPolicy.suggestionRowVerticalPadding)
                                .background(
                                    isSelected
                                            ? selectedBackground
                                            : isHovered
                                            ? tokens.commandPaletteRowHover
                                            : .clear
                                )
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 6)
                                )
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(
                                    selectedIndex == index
                                        ? tokens.primaryText
                                        : tokens.secondaryText
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                                .id(index)
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        if hovering {
                                            hoveredIndex = index
                                        } else {
                                            hoveredIndex = nil
                                        }
                                    }
                                }
                                .onTapGesture { onSelect(suggestion) }
                        }
                    }
                }
                .scrollIndicators(shouldScroll ? .visible : .hidden)
                .frame(height: CommandPaletteLayoutPolicy.suggestionsHeight(for: suggestions.count))
                .onChange(of: selectedIndex) { _, newIndex in
                    guard newIndex >= 0 else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }

        @ViewBuilder
        private func row(
            for suggestion: SearchManager.SearchSuggestion,
            isSelected: Bool,
            selectedForeground: Color,
            selectedChipBackground: Color,
            selectedChipForeground: Color
        ) -> some View {
            switch suggestion.type {
            case .tab(let tab):
                TabSuggestionItem(
                    tab: tab,
                    isSelected: isSelected,
                    selectedForeground: selectedForeground,
                    selectedChipBackground: selectedChipBackground,
                    selectedChipForeground: selectedChipForeground
                )
            case .history(let entry):
                HistorySuggestionItem(
                    entry: entry,
                    isSelected: isSelected,
                    selectedForeground: selectedForeground,
                    onDelete: entry.visitID == nil ? nil : {
                        onDeleteHistoryEntry(entry)
                    }
                )
            case .url:
                GenericSuggestionItem(
                    icon: Image(systemName: "link"),
                    text: suggestion.text,
                    actionLabel: "Open URL",
                    isSelected: isSelected,
                    selectedForeground: selectedForeground,
                    selectedChipBackground: selectedChipBackground,
                    selectedChipForeground: selectedChipForeground
                )
            case .search:
                GenericSuggestionItem(
                    icon: Image(systemName: "magnifyingglass"),
                    text: suggestion.text,
                    isSelected: isSelected,
                    selectedForeground: selectedForeground,
                    selectedChipBackground: selectedChipBackground,
                    selectedChipForeground: selectedChipForeground
                )
            }
        }
    }

    private func deleteHistoryEntry(_ entry: HistoryListItem) {
        guard let visitID = entry.visitID else { return }

        Task { @MainActor in
            await browserManager.historyManager.delete(query: .visits([visitID]))
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                searchManager.clearSuggestions()
            } else {
                searchManager.searchSuggestions(for: trimmed)
            }
        }
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
            let navigateURL: String
            if let url = site.searchURL(for: query) {
                navigateURL = url.absoluteString
            } else {
                // Fallback: search on the site's domain directly
                navigateURL = "https://\(site.domain)/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
            }
            if commandPalette.shouldNavigateCurrentTab
                && browserManager.currentTab(for: windowState) != nil
            {
                browserManager.currentTab(for: windowState)?.loadURL(navigateURL)
            } else {
                browserManager.createNewTab(in: windowState, url: navigateURL)
            }
            text = ""
            activeSiteSearch = nil
            selectedSuggestionIndex = -1
            commandPalette.close(preserveDraft: false)
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
        switch suggestion.type {
        case .tab(let existingTab):
            browserManager.selectTab(existingTab, in: windowState)
            RuntimeDiagnostics.debug(
                "Switched to existing tab: \(existingTab.name)",
                category: "CommandPalette"
            )
        case .history(let historyEntry):
            if commandPalette.shouldNavigateCurrentTab
                && browserManager.currentTab(for: windowState) != nil
            {
                browserManager.currentTab(for: windowState)?.loadURL(
                    historyEntry.url.absoluteString
                )
                RuntimeDiagnostics.debug(
                    "Navigated current tab to history URL: \(historyEntry.url)",
                    category: "CommandPalette"
                )
            } else {
                browserManager.createNewTab(in: windowState, url: historyEntry.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Created new tab from history in window \(windowState.id)",
                    category: "CommandPalette"
                )
            }
        case .url, .search:
            if commandPalette.shouldNavigateCurrentTab
                && browserManager.currentTab(for: windowState) != nil
            {
                browserManager.currentTab(for: windowState)?.navigateToURL(
                    suggestion.text
                )
                RuntimeDiagnostics.debug(
                    "Navigated current tab to: \(suggestion.text)",
                    category: "CommandPalette"
                )
            } else {
                // Normalize the URL/search query first, then create the tab with
                // the correct URL so the webview loads it directly without a race.
                let template = browserManager.sumiSettings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
                let resolved = normalizeURL(suggestion.text, queryTemplate: template)
                browserManager.createNewTab(in: windowState, url: resolved)
                RuntimeDiagnostics.debug(
                    "Created new tab in window \(windowState.id)",
                    category: "CommandPalette"
                )
            }
        }

        text = ""
        activeSiteSearch = nil
        selectedSuggestionIndex = -1
        commandPalette.close(preserveDraft: false)
    }

    private func navigateSuggestions(direction: Int) {
        let maxIndex = visibleSuggestions.count - 1

        if direction > 0 {
            selectedSuggestionIndex = min(selectedSuggestionIndex + 1, maxIndex)
        } else {
            selectedSuggestionIndex = max(selectedSuggestionIndex - 1, -1)
        }
    }

    private func installOutsideClickMonitorIfNeeded() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            CommandPaletteOutsideClickRouting.monitorResult(
                for: event,
                isPaletteVisible: commandPalette.isVisible,
                cardView: paletteCardView
            ) {
                // Close asynchronously and return the original event so sidebar/browser chrome handles this click.
                DispatchQueue.main.async {
                    windowState.window?.makeFirstResponder(nil)
                    isSearchFocused = false
                    commandPalette.close(preserveDraft: true)
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

}

enum CommandPaletteOutsideClickRouting {
    @MainActor
    static func monitorResult(
        for event: NSEvent,
        isPaletteVisible: Bool,
        cardView: NSView?,
        onOutsideClick: () -> Void
    ) -> NSEvent? {
        monitorResult(
            for: event,
            isPaletteVisible: isPaletteVisible,
            isEventInsideCard: isEventInsideCard(event, cardView: cardView),
            onOutsideClick: onOutsideClick
        )
    }

    static func monitorResult(
        for event: NSEvent,
        isPaletteVisible: Bool,
        isEventInsideCard: Bool,
        onOutsideClick: () -> Void
    ) -> NSEvent? {
        guard isPaletteVisible else { return event }
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

private final class CommandPaletteCardBoundsProbeView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct CommandPaletteCardBoundsReader: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CommandPaletteCardBoundsProbeView()
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

private struct CommandPaletteSearchModeGlow: Identifiable {
    let id = UUID()
    let color: Color
}

private struct CommandPaletteSearchModeGlowView: View {
    let glow: CommandPaletteSearchModeGlow
    let progress: CGFloat

    var body: some View {
        let remainingOpacity = max(0, min(1, Double(1 - progress)))
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(glow.color.opacity(0.34 * remainingOpacity), lineWidth: 1)
            .shadow(
                color: glow.color.opacity(0.58 * remainingOpacity),
                radius: 18 + 92 * progress
            )
            .padding(-1)
            .id(glow.id)
    }
}

// MARK: - Local vignette (Zen-like, not full-page dim)

/// Soft shadows only in a band around the card; page corners stay bright (no window-wide scrim).
private struct CommandPaletteLocalVignetteModifier: ViewModifier {
    let chromeScheme: ColorScheme
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .shadow(color: Color.black.opacity(0.165), radius: 16, x: 0, y: 8)
        } else {
            switch chromeScheme {
            case .light:
                content
                    .shadow(color: Color.black.opacity(0.145), radius: 34, x: 0, y: 14)
                    .shadow(color: Color.black.opacity(0.09), radius: 18, x: 0, y: 7)
                    .shadow(color: Color.black.opacity(0.045), radius: 8, x: 0, y: 3)
            case .dark:
                content
                    .shadow(color: Color.black.opacity(0.36), radius: 32, x: 0, y: 14)
                    .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 7)
            @unknown default:
                content
                    .shadow(color: Color.black.opacity(0.145), radius: 34, x: 0, y: 14)
            }
        }
    }
}
