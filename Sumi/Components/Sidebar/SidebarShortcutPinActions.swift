import AppKit

@MainActor
enum SidebarShortcutPinActions {
    static func resetToLaunchURL(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        commands: SidebarPinCommands
    ) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        let preserveCurrentPage = modifiers.contains(.command) || modifiers.contains(.control)
        _ = commands.resetToLaunchURL(
            pin,
            in: windowState,
            preserveCurrentPage: preserveCurrentPage
        )
    }
}
