import AppKit
import Foundation

/// Reopens one browser window from an exact archived window snapshot.
/// Seam for the recovery services that trigger window reopening
/// (recently-closed window items, last-session restore, startup policy,
/// profile switch); the live implementation is `WindowSessionReopenService`.
@MainActor
protocol WindowSessionReopening: AnyObject {
    /// Idempotent by archive identity. Returns `true` when the snapshot is
    /// already open or a new shell was registered and restored; `false` means
    /// the caller must keep its retry/history source.
    @discardableResult
    func reopenWindow(from snapshot: LastSessionWindowSnapshot) async -> Bool
}

/// Serializes idempotent restored-window creation. The injected capability is
/// an atomic prepare/register/activate shell transaction, so no observer can
/// see a default state under an archived window identity.
@MainActor
final class WindowSessionReopenService: WindowSessionReopening {
    private struct PendingReopen {
        let id: UUID
        let task: Task<Bool, Never>
    }

    private let windowRegistry: @MainActor () -> WindowRegistry?
    private let createRestoredWindow: @MainActor (
        LastSessionWindowSnapshot
    ) -> BrowserWindowState?
    private var pendingReopen: PendingReopen?

    init(
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        createRestoredWindow: @escaping @MainActor (
            LastSessionWindowSnapshot
        ) -> BrowserWindowState?
    ) {
        self.windowRegistry = windowRegistry
        self.createRestoredWindow = createRestoredWindow
    }

    @discardableResult
    func reopenWindow(from snapshot: LastSessionWindowSnapshot) async -> Bool {
        let predecessor = pendingReopen?.task
        let operationID = UUID()
        let task = Task { @MainActor [weak self] in
            if let predecessor {
                _ = await predecessor.value
            }
            guard Task.isCancelled == false, let self else { return false }
            return performReopen(from: snapshot)
        }
        pendingReopen = PendingReopen(id: operationID, task: task)

        let didReopen = await task.value
        if pendingReopen?.id == operationID {
            pendingReopen = nil
        }
        return didReopen
    }

    private func performReopen(from snapshot: LastSessionWindowSnapshot) -> Bool {
        guard let registry = windowRegistry() else { return false }
        if registry.allWindows.contains(where: {
            $0.isIncognito == false
                && ($0.restoredSessionWindowId ?? $0.id) == snapshot.id
        }) {
            return true
        }
        guard let targetWindow = createRestoredWindow(snapshot) else {
            return false
        }
        guard registry.windows[targetWindow.id] === targetWindow,
              targetWindow.restoredSessionWindowId == snapshot.id,
              targetWindow.isAwaitingInitialSessionResolution == false else {
            let appKitWindow = registry.appKitWindow(for: targetWindow)
            registry.rollbackRegistration(targetWindow)
            appKitWindow?.close()
            return false
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
