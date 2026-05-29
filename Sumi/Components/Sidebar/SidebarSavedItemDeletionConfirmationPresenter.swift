import AppKit

@MainActor
enum SidebarSavedItemDeletionConfirmationPresenter {
    enum SavedTabKind {
        case essential
        case pinnedTab

        var displayName: String {
            switch self {
            case .essential:
                return "Essential"
            case .pinnedTab:
                return "Pinned Tab"
            }
        }
    }

    static func confirmDeleteSavedTab(
        kind: SavedTabKind,
        title: String,
        url: URL,
        window: NSWindow?,
        onDelete: @escaping @MainActor () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \(kind.displayName)?"
        alert.informativeText = "\(title)\n\(url.absoluteString)\n\nThis removes the saved \(kind.displayName). It does not delete browsing history or website data."
        if let icon = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete \(kind.displayName)") {
            alert.icon = icon
        }

        let deleteButton = alert.addButton(withTitle: "Delete \(kind.displayName)")
        deleteButton.hasDestructiveAction = true

        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"

        run(alert, window: window, onConfirm: onDelete)
    }

    static func confirmDeleteFolder(
        folderName: String,
        childCount: Int,
        window: NSWindow?,
        onDelete: @escaping @MainActor () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete Folder?"
        alert.informativeText = "\(folderName)\n\n\(pinnedTabsText(childCount)) will stay saved outside the folder."
        if let icon = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete Folder") {
            alert.icon = icon
        }

        let deleteButton = alert.addButton(withTitle: "Delete Folder")
        deleteButton.hasDestructiveAction = true

        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"

        run(alert, window: window, onConfirm: onDelete)
    }

    private static func run(
        _ alert: NSAlert,
        window: NSWindow?,
        onConfirm: @escaping @MainActor () -> Void
    ) {
        if let window {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                Task { @MainActor in
                    onConfirm()
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            onConfirm()
        }
    }

    private static func pinnedTabsText(_ count: Int) -> String {
        count == 1 ? "1 pinned tab" : "\(count) pinned tabs"
    }
}
