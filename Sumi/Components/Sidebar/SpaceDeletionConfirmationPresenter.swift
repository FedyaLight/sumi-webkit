import AppKit

@MainActor
enum SpaceDeletionConfirmationPresenter {
    static func confirmDelete(
        space: Space,
        browserManager: BrowserManager,
        window: NSWindow?
    ) {
        guard browserManager.tabManager.spaceStateOwner.spaces.count > 1 else {
            NSSound.beep()
            return
        }

        let alert = makeAlert(
            spaceName: space.name,
            tabsCount: browserManager.tabManager.spaceLauncherProjection.projection(for: space.id).userVisibleTabCount
        )
        alert.sumiApplyNativeSurfaceAppearance(
            windowState: window.flatMap { browserManager.windowRegistry?.windowState(containing: $0) },
            settings: browserManager.sumiSettings
        )
        let spaceID = space.id

        if let window {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                Task { @MainActor in
                    browserManager.tabManager.spaceServices.removal.removeSpace(spaceID)
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            browserManager.tabManager.spaceServices.removal.removeSpace(spaceID)
        }
    }

    private static func makeAlert(spaceName: String, tabsCount: Int) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(spaceName)”?"
        alert.informativeText = informativeText(tabsCount: tabsCount)
        if let icon = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: "Delete Space"
        ) {
            alert.icon = icon
        }

        let deleteButton = alert.addButton(withTitle: "Delete Space")
        deleteButton.hasDestructiveAction = true

        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"

        return alert
    }

    private static func informativeText(tabsCount: Int) -> String {
        if tabsCount == 1 {
            return "1 tab in this space will be permanently deleted. This action cannot be undone."
        }
        return "\(tabsCount) tabs in this space will be permanently deleted. This action cannot be undone."
    }
}
