//
//  CommandPaletteView.swift
//  Sumi
//
//

import AppKit
import Carbon
import SumiDomain
import SwiftUI

struct CommandPaletteView: View {
    let browserContext: CommandPaletteBrowserContext
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(KeyboardShortcutManager.self) private var keyboardShortcutManager
    @State private var searchSession: CommandPaletteSearchSessionOwner
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @FocusState private var isSearchFocused: Bool
    @State private var searchModeConfirmation: CommandPaletteSearchModeConfirmation?
    @State private var nativeInteraction =
        CommandPaletteNativeInteraction()
    @State private var searchFocusRequestID = 0
    @State private var searchFocusSelectAll = false

    init(browserContext: CommandPaletteBrowserContext) {
        self.browserContext = browserContext
        _searchSession = State(
            initialValue: browserContext.makeSearchSession()
        )
    }

    private var siteSearchMatch: SumiSearchEngine? {
        searchSession.siteSearchMatch(in: sumiSettings.searchEngines)
    }

    private var visibleRows: [CommandPaletteRow] {
        searchSession.visibleRows
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
        @Bindable var bindableSearchSession = searchSession
        let isVisible = windowState.presentationState.isCommandPaletteVisible
        let tokens = self.tokens
        let urlBarPlaceholder = urlBarPlaceholderString
        let textFieldFont = ChromeThemeTypography.commandPaletteInput
        let siteSearchMatchID = siteSearchMatch?.id
        let actionsModeAccent = browserContext.spaces
            .accentColor(in: windowState)
            ?? themeContext.sourceWorkspaceTheme.gradientTheme.primaryColor
                .mixed(
                    with: themeContext.targetWorkspaceTheme
                        .gradientTheme.primaryColor,
                    amount: CGFloat(themeContext.transitionProgress)
                )
        let actionsModeBackground =
            CommandPaletteThemeTokens.Colors.actionsModeBackground(
                accent: actionsModeAccent,
                colorScheme: colorScheme
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
                                    systemName: searchSession.mode == .actions
                                        ? "terminal"
                                        : searchSession.activeSiteSearch != nil
                                        ? "magnifyingglass"
                                        : isLikelyURL(searchSession.text)
                                            ? "globe" : "magnifyingglass"
                                )
                                .id(
                                    searchSession.mode == .actions
                                        ? "terminal"
                                        : searchSession.activeSiteSearch != nil
                                            ? "magnifyingglass"
                                            : isLikelyURL(searchSession.text)
                                                ? "globe"
                                                : "magnifyingglass"
                                )
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
                                } else if searchSession.mode == .actions {
                                    Text("Actions")
                                        .font(ChromeThemeTypography.commandPaletteModeToken)
                                        .foregroundStyle(Color.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .lineLimit(1)
                                        .background(actionsModeBackground)
                                        .clipShape(Capsule())
                                        .transition(
                                            CommandPaletteMotionPolicy
                                                .chromeElementTransition(
                                                    for: motionMode
                                                )
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
                                        CommandPaletteTextField(
                                            text: $bindableSearchSession.text,
                                            isFocused: $isSearchFocused,
                                            font: ChromeThemeTypography.commandPaletteInputNSFont,
                                            primaryColor: NSColor(tokens.primaryText),
                                            focusRequestID: searchFocusRequestID,
                                            focusSelectAll: searchFocusSelectAll,
                                            onTab: {
                                                handleTab()
                                            },
                                            onReturn: {
                                                handleReturn()
                                            },
                                            onMoveSelection: { direction in
                                                searchSession.navigateSuggestions(direction: direction)
                                            },
                                            onEscape: {
                                                handleEscape()
                                            },
                                            onDeleteAtEmptySiteSearch: {
                                                guard searchSession.text.isEmpty else {
                                                    return false
                                                }
                                                return leaveScopedMode()
                                            }
                                        )
                                            .tint(tokens.primaryText)
                                            .accessibilityIdentifier("command-palette-input")
                                            .accessibilityLabel("Search")
                                            .onChange(of: searchSession.text) { _, newValue in
                                                // Defer command palette / window session writes so `BrowserWindowState` is not mutated during SwiftUI view updates.
                                                nativeInteraction.scheduleTextChange(in: windowState, text: newValue) { text in
                                                    browserContext.updateCommandPaletteDraft(in: windowState, text: text)
                                                    searchSession.handleTextChanged(
                                                        text,
                                                        isCommandPaletteVisible: windowState.presentationState.isCommandPaletteVisible,
                                                        presentationReason: windowState.commandPalettePresentationReason,
                                                        windowState: windowState
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
                                                        .fill(tokens.floatingSurfaceSecondaryBackground)
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
                                rows: visibleRows,
                                layoutSuggestionCount: suggestionLayoutCount,
                                resultListTopRequestID:
                                    searchSession.resultListTopRequestID,
                                selectedID: $bindableSearchSession.selectedRowID,
                                hoveredID: $bindableSearchSession.hoveredRowID,
                                onSelect: { rowID in
                                    selectRow(rowID)
                                },
                                onDeleteHistory: { query in
                                    deleteHistory(query)
                                }
                            )
                            .animation(
                                chromeContentAnimation,
                                value: suggestionLayoutCount
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
                        .background(tokens.floatingSurfaceBackground)
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
                                    tokens.floatingSurfaceBorder,
                                    lineWidth: 0.5,
                                    antialiased: false
                                )
                        }
                        .modifier(
                            CommandPaletteSearchModeConfirmationModifier(
                                confirmation: searchModeConfirmation
                            )
                        )
                        .modifier(
                            CommandPaletteLocalVignetteModifier(
                                chromeScheme: themeContext.targetChromeColorScheme,
                                reduceTransparency: accessibilityReduceTransparency
                            )
                        )
                        .background(
                            CommandPaletteCardBoundsReader { view in
                                nativeInteraction.updateCardView(view)
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
        .task(id: windowState.presentationState.isCommandPaletteVisible) {
            handleVisibilityChanged(
                windowState.presentationState.isCommandPaletteVisible
            )
        }
        .onDisappear {
            searchSession.cancelPendingSearch()
            nativeInteraction.endSession()
        }
        .onChange(of: browserContext.currentProfileId) { _, _ in
            searchSession.handleProfileContextChanged(
                isCommandPaletteVisible:
                    windowState.presentationState.isCommandPaletteVisible,
                presentationReason:
                    windowState.commandPalettePresentationReason,
                windowState: windowState
            )
            refreshRuntimeCatalogs()
        }
        .onChange(of: searchSession.activeSiteSearch != nil) { _, _ in
            searchSession.commitSuggestionLayoutCountIfReady()
        }
        .onChange(of: windowState.commandPaletteDraftText) { _, newValue in
            if isVisible, newValue != searchSession.text {
                searchSession.text = newValue
                focusSearchField(selectAll: false)
            }
        }
        .onChange(of: windowState.commandPalettePresentationReason) { _, _ in
            if windowState.presentationState.isCommandPaletteVisible {
                refreshAvailableBrowserActions()
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
            nativeInteraction.beginSession(windowID: windowID)
            installEventMonitorIfNeeded()
            refreshRuntimeCatalogs()

            searchSession.text = windowState.commandPaletteDraftText
            refreshEmptyStateSuggestionsIfNeeded()

            nativeInteraction.scheduleFocus(windowID: windowID) {
                guard windowState.id == windowID,
                      windowState.presentationState.isCommandPaletteVisible
                else { return }
                focusSearchField(selectAll: !searchSession.text.isEmpty)
            }
        } else {
            nativeInteraction.endSession()
            isSearchFocused = false
            searchSession.resetForHiddenBar()
            searchModeConfirmation = nil
        }
    }

    private func refreshEmptyStateSuggestionsIfNeeded() {
        searchSession.refreshEmptyStateSuggestionsIfNeeded(
            isCommandPaletteVisible: windowState.presentationState.isCommandPaletteVisible,
            presentationReason: windowState.commandPalettePresentationReason,
            windowState: windowState
        )
    }

    private func focusSearchField(selectAll: Bool) {
        guard windowState.presentationState.isCommandPaletteVisible else { return }
        isSearchFocused = true
        searchFocusSelectAll = selectAll
        searchFocusRequestID &+= 1
    }

    private func enterSiteSearch(_ site: SumiSearchEngine) {
        searchSession.enterSiteSearch(site)
        triggerSearchModeConfirmation(color: site.color)
    }

    private func triggerSearchModeConfirmation(color: Color) {
        guard motionMode == .standard else { return }
        searchModeConfirmation = CommandPaletteSearchModeConfirmation(
            color: color
        )
    }

    private func deleteHistory(_ query: HistoryQuery) {
        Task { @MainActor in
            await browserContext.deleteHistory(query)
            searchSession.reloadAfterHistoryDeletion(
                isCommandPaletteVisible:
                    windowState.presentationState.isCommandPaletteVisible,
                presentationReason:
                    windowState.commandPalettePresentationReason,
                windowState: windowState
            )
        }
    }

    private func handleReturn() {
        guard let intent = searchSession.commitIntentForReturn() else { return }
        performCommitIntent(intent)
    }

    private func selectRow(_ rowID: CommandPaletteRow.ID) {
        guard let intent = searchSession.commitIntent(for: rowID) else {
            return
        }
        performCommitIntent(intent)
    }

    private func performCommitIntent(_ intent: CommandPaletteCommitIntent) {
        switch intent {
        case .browserAction(let action):
            performBrowserAction(action)
        case .space(let spaceID):
            guard let action = browserContext.spaces.shortcutAction(
                for: spaceID,
                in: windowState
            ) else { return }
            performBrowserAction(action)
        case .extensionAction(let extensionID):
            performExtensionAction(extensionID)
        case .siteSearch(let site, let query):
            commitActiveSiteSearch(site, query: query)
        case .browserNavigation(let activation):
            guard nativeInteraction.requestCommit(
                in: windowState,
                perform: {
                    browserContext.commitCommandPaletteActivation(
                        activation,
                        in: windowState
                    )
                }
            ) else { return }
            resetCommittedSearchSession()
        }
    }

    private func performBrowserAction(_ action: ShortcutAction) {
        guard let appKitWindow = windowState.shellWindow(in: windowRegistry)
        else { return }
        nativeInteraction.requestBrowserAction(
            in: windowState,
            canPerform: {
                keyboardShortcutManager.canPerform(
                    action,
                    keyWindow: appKitWindow
                )
            },
            perform: {
                keyboardShortcutManager.performFromCommandPalette(
                    action,
                    keyWindow: appKitWindow
                )
            },
            dismiss: {
                browserContext.dismissCommandPalette(
                    in: windowState,
                    preserveDraft: false
                )
            },
            onPerformed: {
                resetCommittedSearchSession()
            },
            onRejected: {
                refreshAvailableBrowserActions()
            }
        )
    }

    private func refreshAvailableBrowserActions() {
        guard let appKitWindow = windowState.shellWindow(in: windowRegistry)
        else {
            searchSession.updateAvailableBrowserActions(
                [CommandPaletteBrowserActionPresentation]()
            )
            return
        }
        searchSession.updateAvailableBrowserActions(
            keyboardShortcutManager.commandPaletteActionPresentations(
                keyWindow: appKitWindow
            )
        )
    }

    private func refreshRuntimeCatalogs() {
        guard windowState.presentationState.isCommandPaletteVisible else {
            return
        }
        searchSession.updateAvailableSpaces(
            browserContext.spaces.presentations(in: windowState)
        )
        searchSession.updateAvailableExtensionActions(
            browserContext.extensions.presentations(in: windowState)
        )
        refreshAvailableBrowserActions()
    }

    private func performExtensionAction(_ extensionID: String) {
        guard let anchorView = windowState
            .shellWindow(in: windowRegistry)?
            .contentView,
              let invocation = browserContext.extensions.prepareInvocation(
                extensionID: extensionID,
                in: windowState,
                anchorView: anchorView
              ) else {
            return
        }

        guard nativeInteraction.requestCommit(
            in: windowState,
            perform: {
                browserContext.dismissCommandPalette(
                    in: windowState,
                    preserveDraft: false
                )
                Task { @MainActor in
                    await browserContext.extensions.perform(invocation)
                }
            }
        ) else { return }
        resetCommittedSearchSession()
    }

    private func commitActiveSiteSearch(_ site: SumiSearchEngine, query: String) {
        guard !query.isEmpty else { return }
        let navigateURL = resolvedSiteSearchURL(site: site, query: query).absoluteString
        guard nativeInteraction.requestCommit(in: windowState, perform: {
            browserContext.commitCommandPaletteNavigation(
                to: navigateURL,
                in: windowState
            )
        }) else { return }
        resetCommittedSearchSession()
    }

    private func resetCommittedSearchSession() {
        searchSession.resetAfterCommit()
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

    private func installEventMonitorIfNeeded() {
        nativeInteraction.installEventMonitorIfNeeded(
            matching: [
                .keyDown,
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
            ]
        ) { event in
            if event.type == .keyDown {
                return handlePaletteKeyDown(event) ? nil : event
            }
            return nativeInteraction.routeMouseEvent(
                event,
                isCommandPaletteVisible: windowState.presentationState.isCommandPaletteVisible
            ) {
                // Defer the state mutation and return the original event so sidebar/browser chrome handles this click.
                nativeInteraction.requestDismiss(in: windowState) {
                    windowState.shellWindow(in: windowRegistry)?.makeFirstResponder(nil)
                    isSearchFocused = false
                    browserContext.dismissCommandPalette(in: windowState, preserveDraft: true)
                }
            }
        }
    }

    private func handlePaletteKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([
            .command,
            .control,
            .option,
            .shift,
        ])
        guard modifiers.isEmpty else { return false }

        if event.keyCode == UInt16(kVK_Tab) {
            return handleTab()
        }

        if event.keyCode == UInt16(kVK_Escape) {
            handleEscape()
            return true
        }
        return false
    }

    private func handleTab() -> Bool {
        if let match = siteSearchMatch,
           searchSession.activeSiteSearch == nil {
            enterSiteSearch(match)
            return true
        }
        guard searchSession.mode == .everything,
              searchSession.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty else {
            return false
        }
        searchSession.enterActionsMode()
        focusSearchField(selectAll: false)
        return true
    }

    private func handleEscape() {
        if !leaveScopedMode() {
            browserContext.dismissCommandPalette(
                in: windowState,
                preserveDraft: true
            )
        }
    }

    @discardableResult
    private func leaveScopedMode() -> Bool {
        guard searchSession.leaveScopedMode() else {
            return false
        }
        refreshEmptyStateSuggestionsIfNeeded()
        focusSearchField(selectAll: false)
        return true
    }

}
