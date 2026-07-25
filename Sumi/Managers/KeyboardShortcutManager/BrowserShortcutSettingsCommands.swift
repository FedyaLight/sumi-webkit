import SumiDomain

/// Shortcut commands that open the settings surface or write a stored
/// preference. Preference writes need the live settings object, so each one
/// pairs its mutation with the availability question the menu asks — a
/// shortcut is unavailable while settings are not attached, and an appearance
/// mode that is already active is not offered again.
@MainActor
final class BrowserShortcutSettingsCommands {
    private let navigation: BrowserSettingsNavigationService
    private let attachment: BrowserSettingsAttachmentCoordinator

    init(
        navigation: BrowserSettingsNavigationService,
        attachment: BrowserSettingsAttachmentCoordinator
    ) {
        self.navigation = navigation
        self.attachment = attachment
    }

    func openSettings(
        selecting pane: SettingsTabs,
        in windowState: BrowserWindowState
    ) {
        navigation.openSettings(selecting: pane, in: windowState)
    }

    var isAttached: Bool { attachment.settings != nil }

    func toggleTabsOnRight() -> Bool {
        guard let settings = attachment.settings else { return false }
        settings.sidebarPosition =
            settings.sidebarPosition == .left ? .right : .left
        return true
    }

    func applyWindowScheme(_ mode: WindowSchemeMode) -> Bool {
        guard let settings = attachment.settings else { return false }
        settings.windowSchemeMode = mode
        return true
    }

    func canApplyWindowScheme(_ mode: WindowSchemeMode) -> Bool {
        attachment.settings.map { $0.windowSchemeMode != mode } ?? false
    }
}
