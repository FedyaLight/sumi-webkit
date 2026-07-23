//
//  CommandPaletteView.swift
//  Sumi
//
//

import AppKit
import SwiftUI

struct CommandPaletteView: View {
    let browserContext: CommandPaletteBrowserContext
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @State private var searchSession = CommandPaletteSearchSessionOwner()
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @FocusState private var isSearchFocused: Bool
    @State private var searchModeConfirmation: CommandPaletteSearchModeConfirmation?
    @State private var searchModeConfirmationProgress: CGFloat = 1
    @State private var interactionCommitOwner = CommandPaletteInteractionCommitOwner()
    @State private var outsideClickMonitor = ChromeLocalEventMonitor()
    @State private var focusRequestOwner = CommandPaletteFocusRequestOwner()
    @State private var deferredTextOwner = CommandPaletteDeferredTextOwner()
    @State private var searchFocusRequestID = 0
    @State private var searchFocusSelectAll = false

    private var siteSearchMatch: SumiSearchEngine? {
        searchSession.siteSearchMatch(in: sumiSettings.searchEngines)
    }

    private var visibleSuggestions: [SearchManager.SearchSuggestion] {
        searchSession.visibleSuggestions
    }

    private var urlBarPlaceholderString: String {
        searchSession.urlBarPlaceholderString()
    }

    private var isWaitingForSuggestions: Bool {
        searchSession.isWaitingForSuggestions()
    }

    private var visibleSuggestionLayoutCount: Int {
        searchSession.visibleSuggestionLayoutCount
    }

    private var suggestionLayoutCount: Int {
        searchSession.suggestionLayoutCount
    }

    private var shouldShowEmptyStateSuggestions: Bool {
        windowState.commandPalettePresentationReason == .splitTabPicker
            || sumiSettings.commandPaletteEmptyStateMode == .topLinks
    }

    private var chromeContentAnimation: Animation? {
        CommandPaletteMotionPolicy.chromeContentAnimation(for: motionMode)
    }

    private var microAffordanceAnimation: Animation? {
        CommandPaletteMotionPolicy.microAffordanceAnimation(for: motionMode)
    }

    private var motionMode: CommandPaletteMotionPolicy.Mode {
        CommandPaletteMotionPolicy.mode(
            reduceMotion: accessibilityReduceMotion || sumiSettings.shouldReduceChromeMotion
        )
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
        let isVisible = windowState.presentationState.isCommandPaletteVisible
        let tokens = self.tokens
        let urlBarPlaceholder = urlBarPlaceholderString
        let textFieldFont = ChromeThemeTypography.commandPaletteInput
        let siteSearchMatchID = siteSearchMatch?.id
        let textBinding = Binding(
            get: { searchSession.text },
            set: { searchSession.text = $0 }
        )
        let selectedSuggestionBinding = Binding(
            get: { searchSession.selectedSuggestionIndex },
            set: { searchSession.selectedSuggestionIndex = $0 }
        )
        let hoveredSuggestionBinding = Binding(
            get: { searchSession.hoveredSuggestionIndex },
            set: { searchSession.hoveredSuggestionIndex = $0 }
        )

        ZStack {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack {
                        VStack(alignment: .center, spacing: 0) {
                            HStack(spacing: 15) {
                                Image(
                                    systemName: searchSession.activeSiteSearch != nil
                                        ? "magnifyingglass"
                                        : isLikelyURL(searchSession.text)
                                            ? "globe" : "magnifyingglass"
                                )
                                .id(searchSession.activeSiteSearch != nil ? "magnifyingglass" : isLikelyURL(searchSession.text) ? "globe" : "magnifyingglass")
                                .transition(CommandPaletteMotionPolicy.chromeElementTransition(for: motionMode))
                                .font(ChromeThemeTypography.commandPaletteLeadingIcon)
                                .foregroundStyle(tokens.secondaryText)
                                .frame(width: 15)

                                if let site = searchSession.activeSiteSearch {
                                    Text(site.name)
                                        .font(ChromeThemeTypography.commandPaletteToken)
                                        .foregroundStyle(siteSearchTokenForeground(for: site))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .background(site.color)
                                        .clipShape(Capsule())
                                        .transition(
                                            CommandPaletteMotionPolicy.chromeElementTransition(for: motionMode)
                                        )
                                }

                                ZStack(alignment: .trailing) {
                                    ZStack(alignment: .leading) {
                                        if searchSession.text.isEmpty {
                                            Text(urlBarPlaceholder)
                                                .font(textFieldFont)
                                                .foregroundStyle(tokens.secondaryText)
                                                .allowsHitTesting(false)
                                        }
                                        CommandPaletteInlineCompletionTextField(
                                            text: textBinding,
                                            isFocused: $isSearchFocused,
                                            font: ChromeThemeTypography.commandPaletteInputNSFont,
                                            primaryColor: NSColor(tokens.primaryText),
                                            hidesCaret: searchSession.isSuggestionPreviewActive,
                                            movesInsertionPointToEnd: searchSession.isSuggestionPreviewActive,
                                            focusRequestID: searchFocusRequestID,
                                            focusSelectAll: searchFocusSelectAll,
                                            onBeginEditing: {
                                                searchSession.commitSuggestionPreviewForEditing()
                                            },
                                            onTab: {
                                                if searchSession.isSuggestionPreviewActive {
                                                    searchSession.commitSuggestionPreviewForEditing()
                                                    return true
                                                }
                                                if let match = siteSearchMatch, searchSession.activeSiteSearch == nil {
                                                    enterSiteSearch(match)
                                                    return true
                                                }
                                                return false
                                            },
                                            onReturn: {
                                                handleReturn()
                                            },
                                            onMoveSelection: { direction in
                                                searchSession.navigateSuggestions(direction: direction)
                                            },
                                            onEscape: {
                                                if searchSession.activeSiteSearch != nil {
                                                    searchSession.clearActiveSiteSearch(
                                                        chromeContentAnimation: chromeContentAnimation
                                                    )
                                                } else {
                                                    browserContext.dismissCommandPalette(in: windowState, preserveDraft: true)
                                                }
                                            },
                                            onDeleteAtEmptySiteSearch: {
                                                guard searchSession.activeSiteSearch != nil && searchSession.text.isEmpty else { return false }
                                                searchSession.clearActiveSiteSearch(
                                                    chromeContentAnimation: chromeContentAnimation
                                                )
                                                return true
                                            }
                                        )
                                            .tint(tokens.primaryText)
                                            .accessibilityIdentifier("command-palette-input")
                                            .accessibilityLabel("Search")
                                            .onChange(of: searchSession.text) { _, newValue in
                                                // Defer command palette / window session writes so `BrowserWindowState` is not mutated during SwiftUI view updates.
                                                deferredTextOwner.scheduleTextChange(in: windowState, text: newValue) { text in
                                                    browserContext.updateCommandPaletteDraft(in: windowState, text: text)
                                                    searchSession.handleTextChanged(
                                                        text,
                                                        isCommandPaletteVisible: windowState.presentationState.isCommandPaletteVisible,
                                                        presentationReason: windowState.commandPalettePresentationReason,
                                                        emptyStateMode: sumiSettings.commandPaletteEmptyStateMode,
                                                        windowState: windowState,
                                                        chromeContentAnimation: chromeContentAnimation
                                                    )
                                                }
                                            }
                                    }

                                    if searchSession.activeSiteSearch == nil, let match = siteSearchMatch {
                                        HStack(spacing: 6) {
                                            Text("Search \(match.name)")
                                                .font(textFieldFont)
                                                .foregroundStyle(tokens.secondaryText)
                                                .lineLimit(1)
                                                .truncationMode(.tail)

                                            Text("Tab")
                                                .font(ChromeThemeTypography.commandPaletteMicroLabel)
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
                                            CommandPaletteMotionPolicy.chromeElementTransition(for: motionMode)
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
                                .animation(microAffordanceAnimation, value: siteSearchMatchID)
                            }
                            .frame(height: CommandPaletteLayoutPolicy.inputRowHeight)
                            .padding(.vertical, CommandPaletteLayoutPolicy.inputRowVerticalPadding)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusSearchField(selectAll: false)
                            }

                            CommandPaletteResultsPanelView(
                                browserContext: browserContext,
                                tokens: tokens,
                                suggestions: visibleSuggestions,
                                layoutSuggestionCount: suggestionLayoutCount,
                                selectedIndex: selectedSuggestionBinding,
                                hoveredIndex: hoveredSuggestionBinding,
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
                        .frame(width: effectiveCommandPaletteWidth)
                        .background {
                            if isVisible {
                                MouseEventShieldView(
                                    suppressesUnderlyingWebContentHover: true,
                                    cursorPolicy: .none
                                )
                            }
                        }
                        .background(tokens.commandPaletteBackground)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: ChromeLayoutTokens.commandPaletteCornerRadius,
                                style: .continuous
                            ),
                            style: FillStyle(antialiased: false)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: ChromeLayoutTokens.commandPaletteCornerRadius, style: .continuous)
                                .strokeBorder(
                                    tokens.separator,
                                    lineWidth: 1,
                                    antialiased: false
                                )
                        }
                        .overlay {
                            if let confirmation = searchModeConfirmation {
                                CommandPaletteSearchModeConfirmationView(
                                    confirmation: confirmation,
                                    progress: searchModeConfirmationProgress
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
                                interactionCommitOwner.updateCardView(view)
                            }
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("command-palette")
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
            if windowState.presentationState.isCommandPaletteVisible {
                handleVisibilityChanged(true)
            }
        }
        .onChange(of: windowState.presentationState.isCommandPaletteVisible) { _, newVisible in
            handleVisibilityChanged(newVisible)
        }
        .onDisappear {
            searchSession.cancelPendingSearch()
            deferredTextOwner.endSession()
            removeOutsideClickMonitor()
        }
        .onChange(of: browserContext.currentProfileId) { _, _ in
            searchSession.handleProfileContextChanged(
                isCommandPaletteVisible: windowState.presentationState.isCommandPaletteVisible
            )
        }
        .onChange(of: searchSession.visibleSuggestions.count) { _, _ in
            searchSession.handleSuggestionsChanged(chromeContentAnimation: chromeContentAnimation)
        }
        .onChange(of: searchSession.searchManager.isLoadingSuggestions) { _, isLoading in
            searchSession.handleSuggestionLoadingChanged(
                isLoading: isLoading,
                chromeContentAnimation: chromeContentAnimation
            )
        }
        .onChange(of: searchSession.activeSiteSearch != nil) { _, _ in
            searchSession.commitSuggestionLayoutCountIfReady(
                chromeContentAnimation: chromeContentAnimation
            )
        }
        .onChange(of: windowState.commandPaletteDraftText) { _, newValue in
            if isVisible, newValue != searchSession.text {
                searchSession.text = newValue
                focusSearchField(selectAll: false)
            }
        }
        .onChange(of: sumiSettings.commandPaletteEmptyStateMode) { _, _ in
            refreshEmptyStateSuggestionsIfNeeded()
        }
        .onChange(of: windowState.commandPalettePresentationReason) { _, _ in
            if windowState.presentationState.isCommandPaletteVisible {
                searchSession.isCommandSuggestionAllowed =
                    browserContext.offersCommandSuggestions(in: windowState)
            }
            refreshEmptyStateSuggestionsIfNeeded()
        }
    }

    private func availableWindowWidth(from layoutWidth: CGFloat) -> CGFloat {
        let appKitWindow = windowState.shellWindow(in: windowRegistry)
        if let contentWidth = appKitWindow?.contentView?.bounds.width,
           contentWidth > 0 {
            return contentWidth
        }
        if layoutWidth > 0 {
            return layoutWidth
        }
        return appKitWindow?.frame.width ?? 0
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private func siteSearchTokenForeground(for site: SumiSearchEngine) -> Color {
        ThemeContrastResolver.contrastingShade(
            of: site.color,
            targetRatio: 4.5,
            minimumBlend: 0.68
        ) ?? ThemeContrastResolver.preferredForeground(on: site.color)
    }

    private func handleVisibilityChanged(_ newVisible: Bool) {
        if newVisible {
            let windowID = windowState.id
            focusRequestOwner.beginSession(windowID: windowID)
            interactionCommitOwner.beginSession(windowID: windowID)
            deferredTextOwner.beginSession(windowID: windowID)
            installOutsideClickMonitorIfNeeded()
            browserContext.configureSearchManager(searchSession.searchManager)
            searchSession.isCommandSuggestionAllowed =
                browserContext.offersCommandSuggestions(in: windowState)

            searchSession.text = windowState.commandPaletteDraftText
            refreshEmptyStateSuggestionsIfNeeded()

            focusRequestOwner.scheduleDeferredFocus(windowID: windowID) {
                guard windowState.id == windowID,
                      windowState.presentationState.isCommandPaletteVisible
                else { return }
                focusSearchField(selectAll: !searchSession.text.isEmpty)
            }
        } else {
            focusRequestOwner.endSession()
            interactionCommitOwner.endSession()
            deferredTextOwner.endSession()
            removeOutsideClickMonitor()
            isSearchFocused = false
            searchSession.resetForHiddenBar()
            searchModeConfirmation = nil
            searchModeConfirmationProgress = 1
        }
    }

    private func refreshEmptyStateSuggestionsIfNeeded() {
        searchSession.refreshEmptyStateSuggestionsIfNeeded(
            isCommandPaletteVisible: windowState.presentationState.isCommandPaletteVisible,
            presentationReason: windowState.commandPalettePresentationReason,
            emptyStateMode: sumiSettings.commandPaletteEmptyStateMode,
            windowState: windowState,
            chromeContentAnimation: chromeContentAnimation
        )
    }

    private func focusSearchField(selectAll: Bool) {
        guard windowState.presentationState.isCommandPaletteVisible else { return }
        isSearchFocused = true
        searchFocusSelectAll = selectAll
        searchFocusRequestID &+= 1
    }

    private func enterSiteSearch(_ site: SumiSearchEngine) {
        searchSession.enterSiteSearch(site, chromeContentAnimation: chromeContentAnimation)
        triggerSearchModeConfirmation(color: site.color)
    }

    private func triggerSearchModeConfirmation(color: Color) {
        guard let animation = CommandPaletteMotionPolicy.searchModeConfirmationAnimation(for: motionMode),
              let lifetimeNanoseconds = CommandPaletteMotionPolicy.searchModeConfirmationLifetimeNanoseconds(for: motionMode)
        else { return }

        let confirmation = CommandPaletteSearchModeConfirmation(color: color)
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

    private func deleteHistoryEntry(_ entry: HistoryListItem) {
        Task { @MainActor in
            await browserContext.deleteHistoryEntry(entry)
            let trimmed = searchSession.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                refreshEmptyStateSuggestionsIfNeeded()
            } else {
                searchSession.searchManager.searchSuggestions(for: trimmed)
            }
        }
    }

    private func handleReturn() {
        if let site = searchSession.activeSiteSearch {
            commitActiveSiteSearch(site, query: activeSiteSearchReturnQuery())
            return
        }

        if searchSession.selectedSuggestionIndex >= 0
            && searchSession.selectedSuggestionIndex < visibleSuggestions.count {
            let suggestion = visibleSuggestions[searchSession.selectedSuggestionIndex]
            selectSuggestion(suggestion)
        } else {
            let trimmed = searchSession.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let newSuggestion = SearchManager.SearchSuggestion(
                text: trimmed,
                type: isLikelyURL(trimmed) ? .url : .search
            )
            selectSuggestion(newSuggestion)
        }
    }

    private func selectSuggestion(_ suggestion: SearchManager.SearchSuggestion) {
        if let site = searchSession.activeSiteSearch {
            commitActiveSiteSearch(site, query: suggestion.text)
            return
        }

        guard interactionCommitOwner.requestCommit(in: windowState, perform: {
            browserContext.commitCommandPaletteSuggestion(
                suggestion,
                in: windowState
            )
        }) else { return }
        resetCommittedSearchSession()
    }

    private func activeSiteSearchReturnQuery() -> String {
        if searchSession.selectedSuggestionIndex >= 0
            && searchSession.selectedSuggestionIndex < visibleSuggestions.count {
            return visibleSuggestions[searchSession.selectedSuggestionIndex].text
        }
        return searchSession.text
    }

    private func commitActiveSiteSearch(_ site: SumiSearchEngine, query: String) {
        guard !query.isEmpty else { return }
        let navigateURL = resolvedSiteSearchURL(site: site, query: query).absoluteString
        guard interactionCommitOwner.requestCommit(in: windowState, perform: {
            browserContext.commitCommandPaletteNavigation(
                to: navigateURL,
                in: windowState
            )
        }) else { return }
        resetCommittedSearchSession()
    }

    private func resetCommittedSearchSession() {
        searchSession.text = ""
        searchSession.activeSiteSearch = nil
        searchSession.selectedSuggestionIndex = -1
    }

    private func resolvedSiteSearchURL(site: SumiSearchEngine, query: String) -> URL {
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

    private func installOutsideClickMonitorIfNeeded() {
        guard !outsideClickMonitor.isInstalled else { return }
        outsideClickMonitor.install(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            interactionCommitOwner.monitorResult(
                for: event,
                isCommandPaletteVisible: windowState.presentationState.isCommandPaletteVisible
            ) {
                // Defer the state mutation and return the original event so sidebar/browser chrome handles this click.
                interactionCommitOwner.requestDismiss(in: windowState) {
                    windowState.shellWindow(in: windowRegistry)?.makeFirstResponder(nil)
                    isSearchFocused = false
                    browserContext.dismissCommandPalette(in: windowState, preserveDraft: true)
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        outsideClickMonitor.remove()
    }
}
