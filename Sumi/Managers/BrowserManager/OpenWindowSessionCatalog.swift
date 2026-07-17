import Foundation

/// Read-only projection of open regular windows, independent of history policy.
@MainActor
final class OpenWindowSessionCatalog {
    private let windows: WindowRegistry
    private let snapshots: WindowSessionSnapshotFactory

    init(
        windows: WindowRegistry,
        snapshots: WindowSessionSnapshotFactory
    ) {
        self.windows = windows
        self.snapshots = snapshots
    }

    func regularWindowSnapshots(excludingWindowID: UUID?) -> [LastSessionWindowSnapshot] {
        windows.allWindows
            .filter { !$0.isIncognito && $0.id != excludingWindowID }
            .compactMap { windowState in
                LastSessionWindowSnapshot(
                    id: windowState.restorationState.restoredSessionWindowID ?? windowState.id,
                    session: snapshots.make(for: windowState)
                )
            }
    }

    func deterministicRegularWindow(excludingWindowID: UUID) -> BrowserWindowState? {
        windows.allWindows
            .filter { $0.isIncognito == false && $0.id != excludingWindowID }
            .min { $0.id.uuidString < $1.id.uuidString }
    }

    func containsRegularWindow(_ windowState: BrowserWindowState) -> Bool {
        windows.allWindows.contains {
            $0 === windowState && $0.isIncognito == false
        }
    }

    func deterministicRegularWindow() -> BrowserWindowState? {
        windows.allWindows
            .filter { $0.isIncognito == false }
            .min { $0.id.uuidString < $1.id.uuidString }
    }
}
