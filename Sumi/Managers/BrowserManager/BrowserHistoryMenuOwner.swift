import AppKit
import Foundation

@MainActor
final class BrowserHistoryMenuOwner {
    private let requestCollapsedSidebarOverlayDismissalAction: @MainActor () -> Void
    private let confirmClearAllHistoryAction: @MainActor () -> Bool
    private let clearAllHistoryAction: @MainActor () async -> Void
    private let existingWindowIdsAction: @MainActor () -> Set<UUID>
    private let createNewWindowAction: @MainActor () -> Void
    private let awaitNextRegisteredWindowAction: @MainActor (Set<UUID>) async -> BrowserWindowState?
    private let applyWindowSessionSnapshotAction: @MainActor (WindowSessionSnapshot, BrowserWindowState) -> Void
    private let bringWindowToFrontAction: @MainActor (BrowserWindowState) -> Void
    private let activateApplicationAction: @MainActor () -> Void

    init(
        requestCollapsedSidebarOverlayDismissal: @escaping @MainActor () -> Void,
        confirmClearAllHistory: @escaping @MainActor () -> Bool,
        clearAllHistory: @escaping @MainActor () async -> Void,
        existingWindowIds: @escaping @MainActor () -> Set<UUID>,
        createNewWindow: @escaping @MainActor () -> Void,
        awaitNextRegisteredWindow: @escaping @MainActor (Set<UUID>) async -> BrowserWindowState?,
        applyWindowSessionSnapshot: @escaping @MainActor (WindowSessionSnapshot, BrowserWindowState) -> Void,
        bringWindowToFront: @escaping @MainActor (BrowserWindowState) -> Void,
        activateApplication: @escaping @MainActor () -> Void
    ) {
        self.requestCollapsedSidebarOverlayDismissalAction = requestCollapsedSidebarOverlayDismissal
        self.confirmClearAllHistoryAction = confirmClearAllHistory
        self.clearAllHistoryAction = clearAllHistory
        self.existingWindowIdsAction = existingWindowIds
        self.createNewWindowAction = createNewWindow
        self.awaitNextRegisteredWindowAction = awaitNextRegisteredWindow
        self.applyWindowSessionSnapshotAction = applyWindowSessionSnapshot
        self.bringWindowToFrontAction = bringWindowToFront
        self.activateApplicationAction = activateApplication
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            requestCollapsedSidebarOverlayDismissal: { [weak browserManager] in
                browserManager?.chromeBundle.nativeDialogPresentationOwner.requestCollapsedSidebarOverlayDismissal()
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
                        windowState: browserManager?.windowRegistry?.windowState(containing: keyWindow),
                        settings: browserManager?.sumiSettings
                    )
                }
                return alert.runModal() == .alertFirstButtonReturn
            },
            clearAllHistory: { [weak browserManager] in
                await browserManager?.historyManager.clearAll()
            },
            existingWindowIds: { [weak browserManager] in
                browserManager?.windowRegistry.map { Set($0.windows.keys) } ?? []
            },
            createNewWindow: { [weak browserManager] in
                browserManager?.windowSessionBundle.commands.createNewWindow()
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
                    runtime: WindowSessionRuntimeFactory.make(for: browserManager)
                )
            },
            bringWindowToFront: { [weak browserManager] windowState in
                windowState.shellWindow(in: browserManager?.windowRegistry)?
                    .makeKeyAndOrderFront(nil as Any?)
            },
            activateApplication: {
                NSApp.activate(ignoringOtherApps: true)
            }
        )
    }

    func clearAllHistoryFromMenu() {
        requestCollapsedSidebarOverlayDismissalAction()
        guard confirmClearAllHistoryAction() else { return }
        let clearAllHistory = clearAllHistoryAction
        Task { @MainActor in
            await clearAllHistory()
        }
    }

    func reopenWindow(from snapshot: WindowSessionSnapshot) async {
        let existingWindowIds = existingWindowIdsAction()
        createNewWindowAction()
        guard let targetWindow = await awaitNextRegisteredWindowAction(existingWindowIds) else {
            return
        }

        applyWindowSessionSnapshotAction(snapshot, targetWindow)
        bringWindowToFrontAction(targetWindow)
        activateApplicationAction()
    }
}
