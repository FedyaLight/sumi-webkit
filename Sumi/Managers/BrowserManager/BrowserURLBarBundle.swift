@MainActor
final class BrowserURLBarBundle {
    let settingsNavigation: BrowserSettingsNavigationService
    let contextOwner: BrowserURLBarContextOwner
    let commandPalette: CommandPaletteServices

    init(
        settingsNavigation: BrowserSettingsNavigationService,
        contextOwner: BrowserURLBarContextOwner,
        commandPalette: CommandPaletteServices
    ) {
        self.settingsNavigation = settingsNavigation
        self.contextOwner = contextOwner
        self.commandPalette = commandPalette
    }
}
