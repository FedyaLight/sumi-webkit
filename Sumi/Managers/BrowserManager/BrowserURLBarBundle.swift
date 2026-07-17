@MainActor
final class BrowserURLBarBundle {
    let settingsNavigation: BrowserSettingsNavigationService
    let contextOwner: BrowserURLBarContextOwner
    let floatingBar: FloatingBarServices

    init(
        settingsNavigation: BrowserSettingsNavigationService,
        contextOwner: BrowserURLBarContextOwner,
        floatingBar: FloatingBarServices
    ) {
        self.settingsNavigation = settingsNavigation
        self.contextOwner = contextOwner
        self.floatingBar = floatingBar
    }
}
