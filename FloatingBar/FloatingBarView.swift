//
//  FloatingBarView.swift
//  Sumi
//
//

import AppKit
import SwiftUI

struct FloatingBarView: View {
    let browserContext: FloatingBarBrowserContext
    @Environment(BrowserWindowState.self) private var windowState
    @State private var searchSession = FloatingBarSearchSessionOwner()
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @FocusState private var isSearchFocused: Bool
    @State private var searchModeConfirmation: FloatingBarSearchModeConfirmation?
    @State private var searchModeConfirmationProgress: CGFloat = 1
    @State private var interactionCommitOwner = FloatingBarInteractionCommitOwner()
    @State private var outsideClickMonitor = ChromeLocalEventMonitor()
    @State private var focusRequestOwner = FloatingBarFocusRequestOwner()
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
        FloatingBarMotionPolicy.mode(
            reduceMotion: accessibilityReduceMotion || sumiSettings.shouldReduceChromeMotion
        )
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
                                .transition(FloatingBarMotionPolicy.chromeElementTransition(for: motionMode))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(tokens.secondaryText)
                                .frame(width: 15)

                                if let site = searchSession.activeSiteSearch {
                                    Text(site.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(siteSearchTokenForeground(for: site))
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
                                        if searchSession.text.isEmpty {
                                            Text(urlBarPlaceholder)
                                                .font(textFieldFont)
                                                .foregroundStyle(tokens.secondaryText)
                                                .allowsHitTesting(false)
                                        }
                                        FloatingBarInlineCompletionTextField(
                                            text: textBinding,
                                            isFocused: $isSearchFocused,
                                            font: .systemFont(ofSize: 13, weight: .semibold),
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
                                                    browserContext.dismissFloatingBar(in: windowState, preserveDraft: true)
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
                                            .accessibilityIdentifier("floating-bar-input")
                                            .accessibilityLabel("Search")
                                            .onChange(of: searchSession.text) { _, newValue in
                                                // Defer floating bar / window session writes so `BrowserWindowState` is not mutated during SwiftUI view updates.
                                                Task { @MainActor in
                                                    browserContext.updateFloatingBarDraft(in: windowState, text: newValue)
                                                    searchSession.handleTextChanged(
                                                        newValue,
                                                        isFloatingBarVisible: windowState.isFloatingBarVisible,
                                                        presentationReason: windowState.floatingBarPresentationReason,
                                                        emptyStateMode: sumiSettings.floatingBarEmptyStateMode,
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
                                interactionCommitOwner.updateCardView(view)
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
            searchSession.cancelPendingSearch()
            removeOutsideClickMonitor()
        }
        .onChange(of: browserContext.currentProfileId) { _, _ in
            searchSession.handleProfileContextChanged(
                isFloatingBarVisible: windowState.isFloatingBarVisible
            )
        }
        .onChange(of: searchSession.searchManager.suggestions.count) { _, _ in
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
        .onChange(of: windowState.floatingBarDraftText) { _, newValue in
            if isVisible, newValue != searchSession.text {
                searchSession.text = newValue
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
           contentWidth > 0 {
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
            installOutsideClickMonitorIfNeeded()
            browserContext.configureSearchManager(searchSession.searchManager)

            searchSession.text = windowState.floatingBarDraftText
            refreshEmptyStateSuggestionsIfNeeded()

            focusRequestOwner.scheduleDeferredFocus(windowID: windowID) {
                guard windowState.id == windowID,
                      windowState.isFloatingBarVisible
                else { return }
                focusSearchField(selectAll: !searchSession.text.isEmpty)
            }
        } else {
            focusRequestOwner.endSession()
            interactionCommitOwner.endSession()
            removeOutsideClickMonitor()
            isSearchFocused = false
            searchSession.resetForHiddenBar()
            searchModeConfirmation = nil
            searchModeConfirmationProgress = 1
        }
    }

    private func refreshEmptyStateSuggestionsIfNeeded() {
        searchSession.refreshEmptyStateSuggestionsIfNeeded(
            isFloatingBarVisible: windowState.isFloatingBarVisible,
            presentationReason: windowState.floatingBarPresentationReason,
            emptyStateMode: sumiSettings.floatingBarEmptyStateMode,
            windowState: windowState,
            chromeContentAnimation: chromeContentAnimation
        )
    }

    private func focusSearchField(selectAll: Bool) {
        guard windowState.isFloatingBarVisible else { return }
        isSearchFocused = true
        searchFocusSelectAll = selectAll
        searchFocusRequestID &+= 1
    }

    private func enterSiteSearch(_ site: SumiSearchEngine) {
        searchSession.enterSiteSearch(site, chromeContentAnimation: chromeContentAnimation)
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
            let query: String
            if searchSession.selectedSuggestionIndex >= 0
                && searchSession.selectedSuggestionIndex < visibleSuggestions.count {
                query = visibleSuggestions[searchSession.selectedSuggestionIndex].text
            } else {
                query = searchSession.text
            }
            guard !query.isEmpty else { return }
            let navigateURL = resolvedSiteSearchURL(site: site, query: query).absoluteString
            let navigatesCurrentTab = browserContext.floatingBarCommitNavigatesCurrentTab(in: windowState)
            guard interactionCommitOwner.requestCommit(in: windowState, perform: {
                browserContext.commitFloatingBarNavigation(
                    to: navigateURL,
                    in: windowState,
                    navigatesCurrentTab: navigatesCurrentTab
                )
            }) else { return }
            searchSession.text = ""
            searchSession.activeSiteSearch = nil
            searchSession.selectedSuggestionIndex = -1
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
        let navigatesCurrentTab = browserContext.floatingBarCommitNavigatesCurrentTab(in: windowState)
        guard interactionCommitOwner.requestCommit(in: windowState, perform: {
            browserContext.commitFloatingBarSuggestion(
                suggestion,
                in: windowState,
                navigatesCurrentTab: navigatesCurrentTab
            )
        }) else { return }
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
                isFloatingBarVisible: windowState.isFloatingBarVisible
            ) {
                // Defer the state mutation and return the original event so sidebar/browser chrome handles this click.
                interactionCommitOwner.requestDismiss(in: windowState) {
                    windowState.window?.makeFirstResponder(nil)
                    isSearchFocused = false
                    browserContext.dismissFloatingBar(in: windowState, preserveDraft: true)
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        outsideClickMonitor.remove()
    }
}
