import AppKit

@MainActor
enum SpaceClearConfirmationPresenter {
    static func confirmClear(
        space: Space,
        lifecycle: SidebarSpaceLifecycle,
        window: NSWindow?,
        windowState: BrowserWindowState?,
        settings: SumiSettingsService?
    ) {
        guard lifecycle.space(id: space.id) != nil else {
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
                    _ = lifecycle.clearSpace(spaceID)
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            _ = lifecycle.clearSpace(spaceID)
        }
    }

    private static func makeAlert(spaceName: String, tabsCount: Int) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear “\(spaceName)”?"
        alert.informativeText = informativeText(tabsCount: tabsCount)
        if let icon = NSImage(
            systemSymbolName: "eraser",
            accessibilityDescription: "Clear Space"
        ) {
            alert.icon = icon
        }

        let clearButton = alert.addButton(withTitle: "Clear Space")
        clearButton.hasDestructiveAction = true

        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"

        return alert
    }

    private static func informativeText(tabsCount: Int) -> String {
        if tabsCount == 1 {
            return "1 tab, including pinned tabs and folders, will be permanently closed. The space itself will be kept. This action cannot be undone."
        }
        return "\(tabsCount) tabs, including pinned tabs and folders, will be permanently closed. The space itself will be kept. This action cannot be undone."
    }
}
