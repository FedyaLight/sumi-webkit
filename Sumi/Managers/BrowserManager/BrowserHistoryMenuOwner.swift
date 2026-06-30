import AppKit
import Foundation

@MainActor
final class BrowserHistoryMenuOwner {
    struct Dependencies {
        let requestCollapsedSidebarOverlayDismissal: @MainActor () -> Void
        let confirmClearAllHistory: @MainActor () -> Bool
        let clearAllHistory: @MainActor () async -> Void
        let existingWindowIds: @MainActor () -> Set<UUID>
        let createNewWindow: @MainActor () -> Void
        let awaitNextRegisteredWindow: @MainActor (Set<UUID>) async -> BrowserWindowState?
        let applyWindowSessionSnapshot: @MainActor (WindowSessionSnapshot, BrowserWindowState) -> Void
        let bringWindowToFront: @MainActor (BrowserWindowState) -> Void
        let activateApplication: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func clearAllHistoryFromMenu() {
        dependencies.requestCollapsedSidebarOverlayDismissal()
        guard dependencies.confirmClearAllHistory() else { return }
        Task { @MainActor [dependencies] in
            await dependencies.clearAllHistory()
        }
    }

    func reopenWindow(from snapshot: WindowSessionSnapshot) async {
        let existingWindowIds = dependencies.existingWindowIds()
        dependencies.createNewWindow()
        guard let targetWindow = await dependencies.awaitNextRegisteredWindow(existingWindowIds) else {
            return
        }

        dependencies.applyWindowSessionSnapshot(snapshot, targetWindow)
        dependencies.bringWindowToFront(targetWindow)
        dependencies.activateApplication()
    }
}

extension BrowserHistoryMenuOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            requestCollapsedSidebarOverlayDismissal: { [weak browserManager] in
                browserManager?.requestCollapsedSidebarOverlayDismissal()
            },
            confirmClearAllHistory: {
                let alert = NSAlert()
                alert.messageText = "Clear All History"
                alert.informativeText = "This will permanently remove all browsing history for the current profile."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Clear History")
                alert.addButton(withTitle: "Cancel")
                return alert.runModal() == .alertFirstButtonReturn
            },
            clearAllHistory: { [weak browserManager] in
                await browserManager?.historyManager.clearAll()
            },
            existingWindowIds: { [weak browserManager] in
                Set(browserManager?.windowRegistry?.windows.keys.map { $0 } ?? [])
            },
            createNewWindow: { [weak browserManager] in
                browserManager?.createNewWindow()
            },
            awaitNextRegisteredWindow: { [weak browserManager] existingWindowIds in
                await browserManager?.windowRegistry?.awaitNextRegisteredWindow(
                    excluding: existingWindowIds
                )
            },
            applyWindowSessionSnapshot: { [weak browserManager] snapshot, windowState in
                guard let browserManager else { return }
                browserManager.windowSessionService.applyWindowSessionSnapshot(
                    snapshot,
                    to: windowState,
                    delegate: browserManager
                )
            },
            bringWindowToFront: { windowState in
                windowState.window?.makeKeyAndOrderFront(nil as Any?)
            },
            activateApplication: {
                NSApp.activate(ignoringOtherApps: true)
            }
        )
    }
}
