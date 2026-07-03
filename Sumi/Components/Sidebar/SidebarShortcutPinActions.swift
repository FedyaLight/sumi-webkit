import AppKit

@MainActor
enum SidebarShortcutPinActions {
    static func resetToLaunchURL(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        tabManager: TabManager
    ) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        let preserveCurrentPage = modifiers.contains(.command) || modifiers.contains(.control)
        _ = tabManager.shortcutPinCommandOwner.resetShortcutPinToLaunchURL(
            pin,
            in: windowState,
            preserveCurrentPage: preserveCurrentPage
        )
    }
}
