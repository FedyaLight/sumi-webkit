import Foundation

/// Where a committed command-palette destination lands.
enum CommandPaletteCommitTarget {
    case currentPage(Tab)
    case newTab
}

/// Resolves the target a committed destination belongs to and carries it there:
/// either navigating the current page (claiming its split placeholder first) or
/// opening a new tab after sidebar insertion. Every commit path shares this
/// routing so current-page intent cannot diverge between them.
@MainActor
final class CommandPaletteDestinationRouter {
    private let tabOpening: @MainActor () -> (any CommandPaletteTabOpening)?
    private let tabTargets: CommandPaletteTabTargetCommitter
    private let pageNavigation: CommandPalettePageNavigationService
    private let activePageTab: @MainActor (BrowserWindowState) -> Tab?

    init(
        tabOpening: @escaping @MainActor () -> (any CommandPaletteTabOpening)?,
        tabTargets: CommandPaletteTabTargetCommitter,
        pageNavigation: CommandPalettePageNavigationService,
        activePageTab: @escaping @MainActor (BrowserWindowState) -> Tab?
    ) {
        self.tabOpening = tabOpening
        self.tabTargets = tabTargets
        self.pageNavigation = pageNavigation
        self.activePageTab = activePageTab
    }

    func resolveTarget(
        in windowState: BrowserWindowState
    ) -> CommandPaletteCommitTarget {
        guard windowState.commandPaletteDraftNavigatesCurrentTab,
              let activePageTab = activePageTab(windowState)
        else { return .newTab }

        return .currentPage(activePageTab)
    }

    /// Opens the configured new-tab page when the user set one. Returns `false`
    /// when no page is configured and the palette should present its own
    /// new-tab surface instead.
    func openConfiguredNewTabPage(in windowState: BrowserWindowState) -> Bool {
        guard let configuredURL = pageNavigation.configuredNewTabPageURL else {
            return false
        }
        tabOpening()?.createNewTab(in: windowState, url: configuredURL)
        return true
    }

    /// Loads an already-literal URL. `source` labels the provenance for
    /// diagnostics; paths that do not label a source stay silent.
    func openLiteralURL(
        _ urlString: String,
        target: CommandPaletteCommitTarget,
        windowState: BrowserWindowState,
        source: String?
    ) {
        switch target {
        case .currentPage(let tab):
            tabTargets.commitPlaceholder(for: tab, in: windowState.id)
            pageNavigation.loadLiteralURL(
                urlString,
                in: tab,
                windowState: windowState
            )
            guard let source else { return }
            RuntimeDiagnostics.debug(
                "Navigated current tab to \(source) URL: \(urlString)",
                category: "CommandPalette"
            )
        case .newTab:
            tabOpening()?.createNewTabAfterSidebarInsertion(
                in: windowState,
                url: urlString
            )
            guard let source else { return }
            RuntimeDiagnostics.debug(
                "Created new tab from \(source) in window \(windowState.id)",
                category: "CommandPalette"
            )
        }
    }

    /// Navigates raw user input, normalizing it into a URL for the new-tab path.
    func openInput(
        _ input: String,
        target: CommandPaletteCommitTarget,
        windowState: BrowserWindowState
    ) {
        switch target {
        case .currentPage(let tab):
            tabTargets.commitPlaceholder(for: tab, in: windowState.id)
            pageNavigation.navigate(to: input, in: tab, windowState: windowState)
            RuntimeDiagnostics.debug(
                "Navigated current tab to: \(input)",
                category: "CommandPalette"
            )
        case .newTab:
            tabOpening()?.createNewTabAfterSidebarInsertion(
                in: windowState,
                url: pageNavigation.normalizedURLString(for: input)
            )
            RuntimeDiagnostics.debug(
                "Created new tab in window \(windowState.id)",
                category: "CommandPalette"
            )
        }
    }
}
