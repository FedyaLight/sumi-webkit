import AppKit
import Foundation

struct OpenWindowSessionSnapshot {
    let windowState: BrowserWindowState
    let archiveSnapshot: LastSessionWindowSnapshot
}

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
        regularWindowProjection(excludingWindowID: excludingWindowID)
            .map(\.archiveSnapshot)
    }

    func regularWindowProjection(
        excludingWindowID: UUID? = nil
    ) -> [OpenWindowSessionSnapshot] {
        regularWindows(excludingWindowID: excludingWindowID).map { windowState in
            OpenWindowSessionSnapshot(
                windowState: windowState,
                archiveSnapshot: LastSessionWindowSnapshot(
                    id: windowState.restorationState.restoredSessionWindowID
                        ?? windowState.id,
                    session: snapshots.make(for: windowState)
                )
            )
        }
    }

    func regularWindowIDs(excludingWindowID: UUID? = nil) -> Set<UUID> {
        Set(
            regularWindows(excludingWindowID: excludingWindowID).map {
                $0.restorationState.restoredSessionWindowID ?? $0.id
            }
        )
    }

    func deterministicRegularWindow(
        excludingWindowID: UUID? = nil
    ) -> BrowserWindowState? {
        regularWindows(excludingWindowID: excludingWindowID)
            .min { $0.id.uuidString < $1.id.uuidString }
    }

    func containsRegularWindow(_ windowState: BrowserWindowState) -> Bool {
        windows.allWindows.contains {
            $0 === windowState && $0.isIncognito == false
        }
    }

    func appKitWindow(for windowState: BrowserWindowState) -> NSWindow? {
        windows.appKitWindow(for: windowState)
    }

    private func regularWindows(
        excludingWindowID: UUID?
    ) -> [BrowserWindowState] {
        windows.allWindows
            .filter {
                $0.isIncognito == false && $0.id != excludingWindowID
            }
    }
}
