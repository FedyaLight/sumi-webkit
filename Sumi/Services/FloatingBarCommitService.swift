import Foundation

@MainActor
protocol FloatingBarTabOpening: AnyObject {
    @discardableResult
    func createNewTab(in windowState: BrowserWindowState, url: String) -> Tab

    @discardableResult
    func createNewTabAfterSidebarInsertion(
        in windowState: BrowserWindowState,
        url: String
    ) -> Tab
}

extension BrowserTabOpeningOwner: FloatingBarTabOpening {}

/// Commits a captured floating-bar destination. The target is resolved before
/// dismiss resets the draft, preserving current-page intent without coupling
/// presentation state to tab routing.
@MainActor
final class FloatingBarCommitService {
    private enum Target {
        case currentPage(Tab)
        case newTab
    }

    private let presentation: FloatingBarPresentationService
    private let tabOpening: @MainActor () -> (any FloatingBarTabOpening)?
    private let splitPlaceholders:
        @MainActor () -> (any FloatingBarSplitPlaceholderHandling)?
    private let activePageTab: @MainActor (BrowserWindowState) -> Tab?
    private let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
    private let pageNavigation: FloatingBarPageNavigationService

    init(
        presentation: FloatingBarPresentationService,
        tabOpening: @escaping @MainActor () -> (any FloatingBarTabOpening)?,
        splitPlaceholders: @escaping @MainActor
            () -> (any FloatingBarSplitPlaceholderHandling)?,
        activePageTab: @escaping @MainActor (BrowserWindowState) -> Tab?,
        selectTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void,
        pageNavigation: FloatingBarPageNavigationService
    ) {
        self.presentation = presentation
        self.tabOpening = tabOpening
        self.splitPlaceholders = splitPlaceholders
        self.activePageTab = activePageTab
        self.selectTab = selectTab
        self.pageNavigation = pageNavigation
    }

    func openNewTabSurface(in windowState: BrowserWindowState) {
        if let configuredURL = pageNavigation.configuredNewTabPageURL {
            tabOpening()?.createNewTab(in: windowState, url: configuredURL)
        } else {
            presentation.showNewTab(in: windowState)
        }
    }

    func commitNavigatesCurrentTab(in windowState: BrowserWindowState) -> Bool {
        if case .currentPage = resolveTarget(in: windowState) {
            return true
        }
        return false
    }

    func commitSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState
    ) {
        let target = resolveTarget(in: windowState)
        presentation.dismiss(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: false
        )
        openSuggestion(suggestion, in: windowState, target: target)
    }

    func commitNavigation(to urlString: String, in windowState: BrowserWindowState) {
        let target = resolveTarget(in: windowState)
        presentation.dismiss(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: false
        )

        switch target {
        case .currentPage(let tab):
            splitPlaceholders()?.commitEmptySplitPlaceholder(
                tabId: tab.id,
                in: windowState
            )
            pageNavigation.loadLiteralURL(
                urlString,
                in: tab,
                windowState: windowState
            )
            pageNavigation.applySettingsSurfaceNavigation(from: urlString)
        case .newTab:
            tabOpening()?.createNewTabAfterSidebarInsertion(
                in: windowState,
                url: urlString
            )
        }
    }

    func openSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState
    ) {
        openSuggestion(
            suggestion,
            in: windowState,
            target: resolveTarget(in: windowState)
        )
    }

    private func openSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState,
        target: Target
    ) {
        switch suggestion.type {
        case .tab(let existingTab):
            if splitPlaceholders()?.replaceEmptySplitPlaceholder(
                with: existingTab,
                in: windowState
            ) != true {
                selectTab(existingTab, windowState)
            }
            RuntimeDiagnostics.debug(
                "Switched to existing tab: \(existingTab.name)",
                category: "FloatingBar"
            )
        case .history(let historyEntry):
            openURL(
                historyEntry.url.absoluteString,
                source: "history",
                target: target,
                windowState: windowState
            )
        case .bookmark(let bookmark):
            openURL(
                bookmark.url.absoluteString,
                source: "bookmark",
                target: target,
                windowState: windowState
            )
        case .url, .search:
            openInput(
                suggestion.text,
                target: target,
                windowState: windowState
            )
        }
    }

    private func openURL(
        _ urlString: String,
        source: String,
        target: Target,
        windowState: BrowserWindowState
    ) {
        switch target {
        case .currentPage(let tab):
            splitPlaceholders()?.commitEmptySplitPlaceholder(
                tabId: tab.id,
                in: windowState
            )
            pageNavigation.loadLiteralURL(
                urlString,
                in: tab,
                windowState: windowState
            )
            pageNavigation.applySettingsSurfaceNavigation(from: urlString)
            RuntimeDiagnostics.debug(
                "Navigated current tab to \(source) URL: \(urlString)",
                category: "FloatingBar"
            )
        case .newTab:
            tabOpening()?.createNewTabAfterSidebarInsertion(
                in: windowState,
                url: urlString
            )
            RuntimeDiagnostics.debug(
                "Created new tab from \(source) in window \(windowState.id)",
                category: "FloatingBar"
            )
        }
    }

    private func openInput(
        _ input: String,
        target: Target,
        windowState: BrowserWindowState
    ) {
        switch target {
        case .currentPage(let tab):
            splitPlaceholders()?.commitEmptySplitPlaceholder(
                tabId: tab.id,
                in: windowState
            )
            pageNavigation.navigate(to: input, in: tab, windowState: windowState)
            pageNavigation.applySettingsSurfaceNavigation(from: input)
            RuntimeDiagnostics.debug(
                "Navigated current tab to: \(input)",
                category: "FloatingBar"
            )
        case .newTab:
            let resolvedURL = pageNavigation.normalizedURLString(for: input)
            tabOpening()?.createNewTabAfterSidebarInsertion(
                in: windowState,
                url: resolvedURL
            )
            RuntimeDiagnostics.debug(
                "Created new tab in window \(windowState.id)",
                category: "FloatingBar"
            )
        }
    }

    private func resolveTarget(in windowState: BrowserWindowState) -> Target {
        guard windowState.floatingBarDraftNavigatesCurrentTab,
              let activePageTab = activePageTab(windowState)
        else { return .newTab }

        return .currentPage(activePageTab)
    }
}
