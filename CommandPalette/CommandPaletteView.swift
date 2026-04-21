//
//  CommandPaletteView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import AppKit
import SwiftUI

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
    @State private var paletteHostView: NSView?
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

    let commandPaletteWidth: CGFloat = 765
    let commandPaletteHorizontalPadding: CGFloat = 10
    
    /// Active window width
    private var currentWindowWidth: CGFloat {
        return NSApplication.shared.keyWindow?.frame.width ?? 0
    }
    
    /// Check if the command palette fits in the window
    private var isWindowTooNarrow: Bool {
        let requiredWidth = commandPaletteWidth + (commandPaletteHorizontalPadding * 2)
        return currentWindowWidth <= requiredWidth
    }
    
    /// Caclulate the correct command palette width
    private var effectiveCommandPaletteWidth: CGFloat {
        if isWindowTooNarrow {
            return max(200, currentWindowWidth - (commandPaletteHorizontalPadding * 2))
        } else {
            return commandPaletteWidth
        }
    }

    private var urlBarPlaceholderString: String {
        if let site = activeSiteSearch {
            return "Search \(site.name)..."
        }
        return "Search..."
    }

    var body: some View {
        let isVisible = commandPalette.isVisible
        let tokens = self.tokens
        let urlBarPlaceholder = urlBarPlaceholderString
        let textFieldFont = Font.system(size: 13, weight: .semibold)

        return ZStack {
            Color.clear
                .ignoresSafeArea()
                .allowsHitTesting(false)

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
                                            .tint(tokens.accent)
                                            .focused($isSearchFocused)
                                            .onKeyPress(.tab) {
                                                if let match = siteSearchMatch, activeSiteSearch == nil {
                                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                        activeSiteSearch = match
                                                    }
                                                    text = ""
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
                            }
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: activeSiteSearch != nil)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)

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
                                    }
                                )
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .frame(width: effectiveCommandPaletteWidth)
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
                        .modifier(
                            CommandPaletteLocalVignetteModifier(
                                chromeScheme: themeContext.targetChromeColorScheme,
                                reduceTransparency: accessibilityReduceTransparency
                            )
                        )
                        .background(
                            CommandPaletteHostViewReader { view in
                                if paletteHostView !== view {
                                    paletteHostView = view
                                }
                            }
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("floating-urlbar")
                        .animation(
                            .easeInOut(duration: 0.15),
                            value: searchManager.suggestions.count
                        )
                        .padding(CommandPaletteChromeMetrics.vignetteOutset)
                        Spacer()
                    }
                    .frame(
                        width: effectiveCommandPaletteWidth
                            + CommandPaletteChromeMetrics.vignetteOutset * 2,
                        height: 328 + CommandPaletteChromeMetrics.vignetteOutset * 2
                    )

                    Spacer()
                }
                Spacer()
            }

        }
        .allowsHitTesting(isVisible)
        .opacity(isVisible ? 1.0 : 0.0)
        .onChange(of: commandPalette.isVisible) { _, newVisible in
            if newVisible {
                installOutsideClickMonitorIfNeeded()
                searchManager.setTabManager(browserManager.tabManager)
                searchManager.setHistoryManager(browserManager.historyManager)
                searchManager.updateProfileContext()

                text = commandPalette.prefilledText

                DispatchQueue.main.async {
                    isSearchFocused = true
                    DispatchQueue.main.async {
                        NSApplication.shared.sendAction(
                            #selector(NSText.selectAll(_:)),
                            to: nil,
                            from: nil
                        )
                    }
                }
            } else {
                searchDebounceTask?.cancel()
                removeOutsideClickMonitor()
                isSearchFocused = false
                searchManager.clearSuggestions()
                text = ""
                activeSiteSearch = nil
                selectedSuggestionIndex = -1
            }
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
                    isSearchFocused = true
                }
            }
        }
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

    private func isEmoji(_ string: String) -> Bool {
        return string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF)
                || (scalar.value >= 0x2600 && scalar.value <= 0x26FF)
                || (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }

    // MARK: - Suggestions List Subview
    private struct CommandPaletteSuggestionsListView: View {
        let tokens: ChromeThemeTokens
        let suggestions: [SearchManager.SearchSuggestion]
        @Binding var selectedIndex: Int
        @Binding var hoveredIndex: Int?
        let onSelect: (SearchManager.SearchSuggestion) -> Void

        var body: some View {
            LazyVStack(spacing: 5) {
                ForEach(suggestions.indices, id: \.self) { index in
                    let suggestion = suggestions[index]
                    let isHovered = hoveredIndex == index
                    row(for: suggestion, isSelected: selectedIndex == index)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 11)
                        .background(
                            selectedIndex == index
                                    ? tokens.commandPaletteRowSelected
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

        @ViewBuilder
        private func row(
            for suggestion: SearchManager.SearchSuggestion,
            isSelected: Bool
        ) -> some View {
            switch suggestion.type {
            case .tab(let tab):
                TabSuggestionItem(tab: tab, isSelected: isSelected)
            case .history(let entry):
                HistorySuggestionItem(entry: entry, isSelected: isSelected)
            case .url:
                GenericSuggestionItem(
                    icon: Image(systemName: "link"),
                    text: suggestion.text,
                    isSelected: isSelected
                )
            case .search:
                GenericSuggestionItem(
                    icon: Image(systemName: "magnifyingglass"),
                    text: suggestion.text,
                    isSelected: isSelected
                )
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

    private func iconForSuggestion(_ suggestion: SearchManager.SearchSuggestion)
        -> Image
    {
        switch suggestion.type {
        case .tab(let tab):
            return tab.favicon
        case .history:
            return Image(systemName: "globe")
        case .url:
            return Image(systemName: "link")
        case .search:
            return Image(systemName: "magnifyingglass")
        }
    }

    @ViewBuilder
    private func suggestionRow(
        for suggestion: SearchManager.SearchSuggestion,
        isSelected: Bool
    ) -> some View {
        switch suggestion.type {
        case .tab(let tab):
            TabSuggestionItem(tab: tab, isSelected: isSelected)
                .foregroundStyle(tokens.primaryText)
        case .history(let entry):
            HistorySuggestionItem(entry: entry, isSelected: isSelected)
                .foregroundStyle(tokens.primaryText)
        case .url:
            GenericSuggestionItem(
                icon: Image(systemName: "link"),
                text: suggestion.text,
                isSelected: isSelected
            )
            .foregroundStyle(tokens.primaryText)
        case .search:
            GenericSuggestionItem(
                icon: Image(systemName: "magnifyingglass"),
                text: suggestion.text,
                isSelected: isSelected
            )
            .foregroundStyle(tokens.primaryText)
        }
    }

    private func urlForSuggestion(_ suggestion: SearchManager.SearchSuggestion)
        -> URL?
    {
        switch suggestion.type {
        case .history(let entry):
            return entry.url
        default:
            return nil
        }
    }

    private func isTabSuggestion(_ suggestion: SearchManager.SearchSuggestion)
        -> Bool
    {
        switch suggestion.type {
        case .tab:
            return true
        case .search, .url, .history:
            return false
        }
    }

    private func installOutsideClickMonitorIfNeeded() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            guard commandPalette.isVisible else { return event }

            guard let paletteHostView else {
                return event
            }

            let clickedInsidePalette: Bool = {
                guard let eventWindow = event.window else { return false }
                guard paletteHostView.window === eventWindow else { return false }
                let localPoint = paletteHostView.convert(event.locationInWindow, from: nil)
                return paletteHostView.bounds.contains(localPoint)
            }()

            if !clickedInsidePalette {
                DispatchQueue.main.async {
                    paletteHostView.window?.makeFirstResponder(nil)
                    isSearchFocused = false
                    commandPalette.close(preserveDraft: true)
                }
            }

            return event
        }
    }

    private func removeOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }
}

private struct CommandPaletteHostViewReader: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
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

// MARK: - Local vignette (Zen-like, not full-page dim)

private enum CommandPaletteChromeMetrics {
    /// Keeps multi-layer shadows from clipping against the fixed palette frame.
    static let vignetteOutset: CGFloat = 40
}

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
                    .shadow(color: Color.black.opacity(0.18), radius: 58, x: 0, y: 26)
                    .shadow(color: Color.black.opacity(0.105), radius: 28, x: 0, y: 13)
                    .shadow(color: Color.black.opacity(0.052), radius: 12, x: 0, y: 6)
            case .dark:
                content
                    .shadow(color: Color.black.opacity(0.42), radius: 48, x: 0, y: 22)
                    .shadow(color: Color.black.opacity(0.21), radius: 22, x: 0, y: 10)
            @unknown default:
                content
                    .shadow(color: Color.black.opacity(0.18), radius: 50, x: 0, y: 22)
            }
        }
    }
}
