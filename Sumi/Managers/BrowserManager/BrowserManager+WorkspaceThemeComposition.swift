import Foundation

@MainActor
extension BrowserManager {
    func composeWorkspaceThemeEditor() -> BrowserWorkspaceThemeEditorOwner {
        BrowserWorkspaceThemeEditorOwner(
            workspaceAppearanceService: WorkspaceAppearanceService(),
            contexts: BrowserWorkspaceAppearanceContextFactory(
                spaces: spaceStateOwner,
                windows: windowRegistry,
                transitions: workspaceThemeTransitionOwner,
                persistence: structuralPersistence,
                modal: nativeModalTransaction
            ),
            presentation: workspaceThemePickerPresentation,
            windows: windowRegistry
        )
    }
}
