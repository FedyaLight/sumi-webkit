@MainActor
final class BrowserURLBarBundle {
    let settingsNavigation: BrowserSettingsNavigationService
    let contextOwner: BrowserURLBarContextOwner
    let commandPalettePresentation: CommandPalettePresentationService
    let commandPaletteCommit: CommandPaletteCommitService
    let commandPaletteBrowserContext: CommandPaletteBrowserContextFactory

    init(
        settingsNavigation: BrowserSettingsNavigationService,
        contextOwner: BrowserURLBarContextOwner,
        commandPalettePresentation: CommandPalettePresentationService,
        commandPaletteCommit: CommandPaletteCommitService,
        commandPaletteBrowserContext: CommandPaletteBrowserContextFactory
    ) {
        self.settingsNavigation = settingsNavigation
        self.contextOwner = contextOwner
        self.commandPalettePresentation = commandPalettePresentation
        self.commandPaletteCommit = commandPaletteCommit
        self.commandPaletteBrowserContext = commandPaletteBrowserContext
    }
}
