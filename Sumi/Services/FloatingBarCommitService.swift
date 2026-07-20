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
    private let tabTargets: FloatingBarTabTargetCommitter
    private let activePageTab: @MainActor (BrowserWindowState) -> Tab?
    private let pageNavigation: FloatingBarPageNavigationService
    private let newSplitView: @MainActor (BrowserWindowState) -> Void

    init(
        presentation: FloatingBarPresentationService,
        tabOpening: @escaping @MainActor () -> (any FloatingBarTabOpening)?,
        tabTargets: FloatingBarTabTargetCommitter,
        activePageTab: @escaping @MainActor (BrowserWindowState) -> Tab?,
        pageNavigation: FloatingBarPageNavigationService,
        newSplitView: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.presentation = presentation
        self.tabOpening = tabOpening
        self.tabTargets = tabTargets
        self.activePageTab = activePageTab
        self.pageNavigation = pageNavigation
        self.newSplitView = newSplitView
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
        if case .tab = suggestion.type {
            guard openSuggestion(
                suggestion,
                in: windowState,
                target: target
            ) else { return }
            presentation.dismiss(
                in: windowState,
                preserveDraft: false,
                cancelEmptySplitPlaceholder: false
            )
            return
        }
        presentation.dismiss(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: false
        )
        _ = openSuggestion(suggestion, in: windowState, target: target)
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
            tabTargets.commitPlaceholder(for: tab, in: windowState.id)
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
        _ = openSuggestion(
            suggestion,
            in: windowState,
            target: resolveTarget(in: windowState)
        )
    }

    @discardableResult
    private func openSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState,
        target: Target
    ) -> Bool {
        switch suggestion.type {
        case .tab(let existingTab):
            guard tabTargets.select(existingTab, in: windowState) else {
                return false
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
        case .command(let command):
            switch command {
            case .newSplitView:
                newSplitView(windowState)
            }
        }
        return true
    }

    private func openURL(
        _ urlString: String,
        source: String,
        target: Target,
        windowState: BrowserWindowState
    ) {
        switch target {
        case .currentPage(let tab):
            tabTargets.commitPlaceholder(for: tab, in: windowState.id)
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
            tabTargets.commitPlaceholder(for: tab, in: windowState.id)
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
