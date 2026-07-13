import AppKit

@MainActor
enum SpaceDeletionConfirmationPresenter {
    static func confirmDelete(
        space: Space,
        lifecycle: SidebarSpaceLifecycle,
        window: NSWindow?,
        windowState: BrowserWindowState?,
        settings: SumiSettingsService?
    ) {
        guard lifecycle.canDeleteSpace() else {
            NSSound.beep()
            return
        }

        let alert = makeAlert(
            spaceName: space.name,
            tabsCount: lifecycle.userVisibleTabCount(in: space.id)
        )
        if let settings {
            alert.sumiApplyNativeSurfaceAppearance(
                windowState: windowState,
                settings: settings
            )
        }
        let spaceID = space.id

        if let window {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                Task { @MainActor in
                    _ = lifecycle.removeSpace(spaceID)
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            _ = lifecycle.removeSpace(spaceID)
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
