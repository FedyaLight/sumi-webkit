import Foundation

@MainActor
final class BrowserTabSelectionChromeEffects {
    private let state: BrowserTabSelectionStateApplication
    private let windowSpaceContext: BrowserWindowSpaceContextSynchronizer
    private let workspaceThemes: BrowserWorkspaceThemeTransitionOwner
    private let settings: BrowserSettingsState
    private let commandPalette: CommandPalettePresentationService

    init(
        state: BrowserTabSelectionStateApplication,
        windowSpaceContext: BrowserWindowSpaceContextSynchronizer,
        workspaceThemes: BrowserWorkspaceThemeTransitionOwner,
        settings: BrowserSettingsState,
        commandPalette: CommandPalettePresentationService
    ) {
        self.state = state
        self.windowSpaceContext = windowSpaceContext
        self.workspaceThemes = workspaceThemes
        self.settings = settings
        self.commandPalette = commandPalette
    }

    func publish(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        previousSpaceID: UUID?,
        updateTheme: Bool,
        reconcileSplitSelection: Bool
    ) {
        commandPalette.dismissAfterSelection(in: windowState)
        if reconcileSplitSelection {
            state.reconcileSplitSelection(for: tab, in: windowState)
        }

        windowSpaceContext.synchronize(windowState)
        if updateTheme && shouldUpdateWorkspaceTheme(for: windowState) {
            updateWorkspaceTheme(
                in: windowState,
                previousSpaceID: previousSpaceID
            )
        }

        if tab.representsSumiSettingsSurface {
            settings.settings?.applyNavigationFromSettingsSurfaceURL(tab.url)
        }
    }

    func publishEmptyState(in windowState: BrowserWindowState) {
        windowSpaceContext.synchronize(windowState)
    }

    private func updateWorkspaceTheme(
        in windowState: BrowserWindowState,
        previousSpaceID: UUID?
    ) {
        guard let currentSpace = state.space(windowState.currentSpaceId) else {
            workspaceThemes.updateWorkspaceTheme(
                for: windowState,
                to: .default,
                animate: false
            )
            return
        }
        workspaceThemes.updateWorkspaceTheme(
            for: windowState,
            to: currentSpace.workspaceTheme,
            animate: previousSpaceID != currentSpace.id
        )
    }

    private func shouldUpdateWorkspaceTheme(
        for windowState: BrowserWindowState
    ) -> Bool {
        guard windowState.isInteractiveSpaceTransition else { return true }
        return windowState.currentSpaceId
            != windowState.spaceTransitionSourceSpaceId
    }
}
