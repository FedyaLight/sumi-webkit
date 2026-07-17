import AppKit
import Foundation

/// Presents and executes the user-requested "clear all history" command.
@MainActor
final class BrowserHistoryClearCommand {
    private let requestCollapsedSidebarDismissal: @MainActor () -> Void
    private let confirmClearAllHistory: @MainActor () -> Bool
    private let clearAllHistory: @MainActor () async -> Void

    init(
        requestCollapsedSidebarDismissal: @escaping @MainActor () -> Void,
        confirmClearAllHistory: @escaping @MainActor () -> Bool,
        clearAllHistory: @escaping @MainActor () async -> Void
    ) {
        self.requestCollapsedSidebarDismissal = requestCollapsedSidebarDismissal
        self.confirmClearAllHistory = confirmClearAllHistory
        self.clearAllHistory = clearAllHistory
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            requestCollapsedSidebarDismissal: { [weak browserManager] in
                browserManager?.chromeBundle.nativeDialogPresentationOwner
                    .requestCollapsedSidebarOverlayDismissal()
            },
            confirmClearAllHistory: { [weak browserManager] in
                let alert = NSAlert()
                alert.messageText = "Clear All History"
                alert.informativeText = "This will permanently remove all browsing history for the current profile."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Clear History")
                alert.addButton(withTitle: "Cancel")
                if let keyWindow = NSApp.keyWindow {
                    alert.sumiApplyNativeSurfaceAppearance(
                        windowState: browserManager?.windowRegistry.windowState(
                            containing: keyWindow
                        ),
                        settings: browserManager?.sumiSettings
                    )
                }
                return alert.runModal() == .alertFirstButtonReturn
            },
            clearAllHistory: { [weak browserManager] in
                await browserManager?.historyManager.clearAll()
            }
        )
    }

    func execute() {
        requestCollapsedSidebarDismissal()
        guard confirmClearAllHistory() else { return }
        let clearAllHistory = clearAllHistory
        Task { @MainActor in
            await clearAllHistory()
        }
    }
}
